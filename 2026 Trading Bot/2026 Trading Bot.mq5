//+------------------------------------------------------------------+
//|                                           2026 Trading Bot.mq5   |
//|                                            Manna Mindset Tools   |
//+------------------------------------------------------------------+
#property copyright "Manna Mindset"
#property version   "8.00"
#property strict

#include <Trade/Trade.mqh>

//==================================================================
//                           INPUT SETTINGS
//==================================================================

input group "--- TRADING STRATEGY ---"
input bool   InpEnableTrading = true;        // Enable Auto-Trading?
input double InpRiskPercent   = 1.0;         // Risk % per trade
input int    InpMaxPositions  = 3;           // Max Stacked Positions
input int    InpCooldownMinutes = 30;        // Wait time between stacked trades
input int    InpSlippage      = 3;           // Max Slippage

input group "--- TIME MANAGEMENT ---"
input bool   InpCloseAtDayEnd = true;        // Close trades at end of day?
input int    InpCloseHour     = 23;          // Hour to close (Server Time)
input int    InpCloseMinute   = 50;          // Minute to close

input group "--- RSI DIVERGENCE SETTINGS ---"
input int    InpRSI_Period    = 14;          // RSI Period
input int    InpDivLookback   = 30;          // Bars to scan for divergence
input int    InpSwingSize     = 2;           // Bars to define a Peak/Valley

input group "--- PIVOT SETTINGS ---"
input color  InpColorPP       = clrWhite;    // Pivot Point Color
input color  InpColorRes      = clrLimeGreen;// Resistance Color
input color  InpColorSup      = clrTomato;   // Support Color

input group "--- VISUALS ---"
input bool   InpShowBranding  = true;        // Show Dashboard
input color  InpClrBack       = clrBlack;
input color  InpClrBull       = clrLimeGreen;
input color  InpClrBear       = clrTomato;

//==================================================================
//                           GLOBALS
//==================================================================
CTrade   trade;
int      magicNum = 888;
int      hRSI; // Daily MA handle removed

struct SMarketData {
   double bid, ask;
   double vwap;
   double rsi;
   double r1, s1, pp;

   bool   divBull, divBear;
   bool   buySignal, sellSignal;
   string failReason;
};

// Forward declaration of classes (Standard C++ / MQL5 practice)
// However, since MQL5 requires definitions for instantiation, we will move the class definitions ABOVE OnInit.

//==================================================================
// CLASS DEFINITIONS (Moved up for visibility)
//==================================================================

//==================================================================
// CLASS: RISK MANAGEMENT
//==================================================================
class CRiskManager;
CRiskManager *Risk; // Global declaration here so it's visible to subsequent classes

class CRiskManager
{
public:
   double CalculateDynamicLots(double entryPrice, double slPrice)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      int losses     = GetConsecutiveLosses();

      double riskFactor = MathPow(2, losses);
      double adjRisk    = InpRiskPercent / riskFactor;
      double riskMoney  = balance * (adjRisk / 100.0);

      double slDist = MathAbs(entryPrice - slPrice);
      if(slDist == 0) return 0.01;

      double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickVal == 0 || tickSize == 0) return 0.01;

      double rawLots = riskMoney / ( (slDist / tickSize) * tickVal );

      double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double lots    = MathFloor(rawLots / step) * step;
      double min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double max = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

      if(lots < min) lots = min;
      if(lots > max) lots = max;

      return lots;
   }

   int GetConsecutiveLosses()
   {
      if(!HistorySelect(0, TimeCurrent())) return 0;
      int total = HistoryDealsTotal();
      int losses = 0;
      for(int i = total - 1; i >= 0; i--) {
         ulong ticket = HistoryDealGetTicket(i);
         if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != magicNum) continue;
         if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
         if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         if(profit < 0) losses++;
         else if(profit > 0) break;
      }
      return losses;
   }
};

//==================================================================
// CLASS: STRATEGY LOGIC
//==================================================================
class CStrategy
{
private:
   double      m_buffRSI[];
   double      m_low[], m_high[];
   SMarketData m_data;
   datetime    m_lastTradeTime;

public:
   CStrategy() { m_lastTradeTime = 0; }

   void RunLogic()
   {
      if(!RefreshData()) return;
      CalculateIndicators();
      CheckDivergence();

      m_data.buySignal = false;
      m_data.sellSignal = false;
      m_data.failReason = "Scanning...";

      // --- BUY LOGIC ---
      // 1. Price > VWAP
      // 2. Price inside Pivot-R1 Zone
      // 3. Bullish Divergence
      bool buyTrend  = (m_data.bid > m_data.vwap);
      bool buyZone   = (m_data.bid > m_data.pp && m_data.bid < m_data.r1);
      bool buyDiv    = m_data.divBull;

      if(buyTrend && buyZone && buyDiv) {
         m_data.buySignal = true;
         m_data.failReason = "BUY SIGNAL VALID";
      }
      else if(buyDiv) {
         if(!buyTrend) m_data.failReason = "Bull Div ignored: Below VWAP";
         if(!buyZone)  m_data.failReason = "Bull Div ignored: Bad Zone (Not >PP & <R1)";
      }

      // --- SELL LOGIC ---
      // 1. Price < VWAP
      // 2. Price inside Pivot-S1 Zone
      // 3. Bearish Divergence
      bool sellTrend = (m_data.bid < m_data.vwap);
      bool sellZone  = (m_data.bid < m_data.pp && m_data.bid > m_data.s1);
      bool sellDiv   = m_data.divBear;

      if(sellTrend && sellZone && sellDiv) {
         m_data.sellSignal = true;
         m_data.failReason = "SELL SIGNAL VALID";
      }
      else if(sellDiv) {
         if(!sellTrend) m_data.failReason = "Bear Div ignored: Above VWAP";
         if(!sellZone)  m_data.failReason = "Bear Div ignored: Bad Zone (Not <PP & >S1)";
      }

      // EXECUTION CHECK
      MqlDateTime dt; TimeCurrent(dt);
      bool isEndOfDay = (InpCloseAtDayEnd && dt.hour >= InpCloseHour && dt.min >= InpCloseMinute);

      bool onCooldown = (TimeCurrent() - m_lastTradeTime) < (InpCooldownMinutes * 60);
      if(onCooldown) m_data.failReason = "Cooldown Active (" + IntegerToString(InpCooldownMinutes) + "m)";

      if(InpEnableTrading && !isEndOfDay && !onCooldown && PositionsTotal() < InpMaxPositions)
      {
         ExecuteTrade();
      }
   }

   void ExecuteTrade()
   {
      double slPrice = 0, tpPrice = 0, entryPrice = 0, lots = 0;

      if(m_data.buySignal)
      {
         entryPrice = m_data.ask;
         slPrice    = m_data.pp;
         tpPrice    = m_data.r1;

         if(slPrice >= entryPrice || tpPrice <= entryPrice) return;

         // Needs access to Risk global pointer
         if(CheckPointer(Risk) == POINTER_DYNAMIC) {
             lots = Risk->CalculateDynamicLots(entryPrice, slPrice);
             if(trade.Buy(lots, _Symbol, entryPrice, slPrice, tpPrice, "Div Buy"))
                m_lastTradeTime = TimeCurrent();
         }
      }
      else if(m_data.sellSignal)
      {
         entryPrice = m_data.bid;
         slPrice    = m_data.pp;
         tpPrice    = m_data.s1;

         if(slPrice <= entryPrice || tpPrice >= entryPrice) return;

         if(CheckPointer(Risk) == POINTER_DYNAMIC) {
             lots = Risk->CalculateDynamicLots(entryPrice, slPrice);
             if(trade.Sell(lots, _Symbol, entryPrice, slPrice, tpPrice, "Div Sell"))
                m_lastTradeTime = TimeCurrent();
         }
      }
   }

   // --- INDICATOR CALCULATIONS ---
   void CalculateIndicators() {
      m_data.bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      m_data.ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double h = iHigh(_Symbol, PERIOD_D1, 1);
      double l = iLow(_Symbol, PERIOD_D1, 1);
      double c = iClose(_Symbol, PERIOD_D1, 1);
      m_data.pp = (h + l + c) / 3.0;
      m_data.r1 = 2 * m_data.pp - l;
      m_data.s1 = 2 * m_data.pp - h;

      m_data.rsi     = m_buffRSI[0];
      m_data.vwap    = CalculateVWAP();
   }

   double CalculateVWAP() {
      int startBar = iBarShift(_Symbol, PERIOD_CURRENT, iTime(_Symbol, PERIOD_D1, 0));
      int limit = startBar;
      double cumPV = 0, cumVol = 0;
      for(int i = limit; i >= 0; i--) {
         double p = iClose(_Symbol, PERIOD_CURRENT, i);
         double v = (double)iTickVolume(_Symbol, PERIOD_CURRENT, i);
         cumPV  += p * v;
         cumVol += v;
      }
      return (cumVol > 0) ? cumPV / cumVol : 0;
   }

   // --- DIVERGENCE ENGINE ---
   void CheckDivergence()
   {
      m_data.divBull = false; m_data.divBear = false;
      int trough1 = -1, trough2 = -1;
      int peak1   = -1, peak2   = -1;

      // Bullish
      for(int i = 1; i < InpDivLookback; i++) {
         if(IsSwingLow(i)) {
            if(trough1 == -1) trough1 = i;
            else if(trough2 == -1) { trough2 = i; break; }
         }
      }
      if(trough1 != -1 && trough2 != -1) {
         if(m_low[trough1] < m_low[trough2] && m_buffRSI[trough1] > m_buffRSI[trough2]) {
            if(trough1 <= 5) m_data.divBull = true;
         }
      }

      // Bearish
      for(int i = 1; i < InpDivLookback; i++) {
         if(IsSwingHigh(i)) {
            if(peak1 == -1) peak1 = i;
            else if(peak2 == -1) { peak2 = i; break; }
         }
      }
      if(peak1 != -1 && peak2 != -1) {
         if(m_high[peak1] > m_high[peak2] && m_buffRSI[peak1] < m_buffRSI[peak2]) {
            if(peak1 <= 5) m_data.divBear = true;
         }
      }
   }

   bool IsSwingLow(int i) {
      if(i < InpSwingSize || i > InpDivLookback - InpSwingSize) return false;
      double val = m_low[i];
      for(int k = 1; k <= InpSwingSize; k++) {
         if(m_low[i-k] <= val || m_low[i+k] <= val) return false;
      }
      return true;
   }

   bool IsSwingHigh(int i) {
      if(i < InpSwingSize || i > InpDivLookback - InpSwingSize) return false;
      double val = m_high[i];
      for(int k = 1; k <= InpSwingSize; k++) {
         if(m_high[i-k] >= val || m_high[i+k] >= val) return false;
      }
      return true;
   }

   bool RefreshData() {
      int count = InpDivLookback + 5;
      if(CopyBuffer(hRSI, 0, 0, count, m_buffRSI) <= 0) return false;
      if(CopyLow(_Symbol, PERIOD_CURRENT, 0, count, m_low) <= 0) return false;
      if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, count, m_high) <= 0) return false;

      ArraySetAsSeries(m_buffRSI, true);
      ArraySetAsSeries(m_low, true); ArraySetAsSeries(m_high, true);
      return true;
   }

   SMarketData GetData() { return m_data; }
};

//==================================================================
// CLASS: VISUALS
//==================================================================
class CVisuals
{
public:
   void SetupChartColors() {
      ChartSetInteger(0, CHART_MODE, CHART_CANDLES);
      ChartSetInteger(0, CHART_SHOW_GRID, false);
      ChartSetInteger(0, CHART_COLOR_BACKGROUND, InpClrBack);
      ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrWhite);
      ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, InpClrBear);
      ChartSetInteger(0, CHART_COLOR_CHART_DOWN, InpClrBear);
      ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, InpClrBull);
      ChartSetInteger(0, CHART_COLOR_CHART_UP, InpClrBull);
      ChartRedraw(0);
   }

   void DrawPivots() {
      ObjectsDeleteAll(0, "DGT");
      double h = iHigh(_Symbol, PERIOD_D1, 1);
      double l = iLow(_Symbol, PERIOD_D1, 1);
      double c = iClose(_Symbol, PERIOD_D1, 1);
      double pp=(h+l+c)/3.0;
      CreatePivotLine("PP", pp, InpColorPP, 2);
      CreatePivotLine("R1", 2*pp-l, InpColorRes, 1);
      CreatePivotLine("S1", 2*pp-h, InpColorSup, 1);
   }

   void CreatePivotLine(string name, double price, color col, int width) {
      datetime t1=iTime(_Symbol, PERIOD_D1, 0);
      datetime t2=t1+PeriodSeconds(PERIOD_D1);
      string n="DGT "+name;
      if(ObjectFind(0, n)<0) ObjectCreate(0, n, OBJ_TREND, 0, t1, price, t2, price);
      else {
         ObjectSetDouble(0, n, OBJPROP_PRICE, 0, price); ObjectSetInteger(0, n, OBJPROP_TIME, 0, t1);
         ObjectSetDouble(0, n, OBJPROP_PRICE, 1, price); ObjectSetInteger(0, n, OBJPROP_TIME, 1, t2);
      }
      ObjectSetInteger(0, n, OBJPROP_COLOR, col);
      ObjectSetInteger(0, n, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, false);
      ObjectSetString(0, n, OBJPROP_TEXT, "  "+name);
   }

   void DrawBranding() {
      string objName = "MannaBrandLogo";
      if(ObjectFind(0, objName) < 0) ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
      ObjectSetString(0, objName, OBJPROP_TEXT, "MANNA MINDSET");
      ObjectSetString(0, objName, OBJPROP_FONT, "Impact");
      ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 18);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, clrGold);
      ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, 20);
      ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, 350);
   }

   // FIX: Changed SMarketData &d to SMarketData d (pass by value)
   // This allows passing the temporary return value from Strategy->GetData()
   void UpdateDashboard(SMarketData d) {
      int losses = 0;
      if(CheckPointer(Risk) == POINTER_DYNAMIC) {
         losses = Risk->GetConsecutiveLosses();
      }

      string text = "================================\n";
      text += "   2026 TRADING BOT (v8.0)       \n";
      text += "================================\n";
      text += "STATUS: " + d.failReason + "\n\n";

      text += "--- ACTIVE SETTINGS ------------\n";
      text += "Positions: " + IntegerToString(PositionsTotal()) + " / " + IntegerToString(3) + "\n";
      text += "Closes at: " + IntegerToString(23) + ":50\n\n";

      text += "--- MARKET FILTERS -------------\n";
      text += "VWAP:        " + ((d.bid > d.vwap) ? "Bullish" : "Bearish") + "\n";
      text += "Pivot Zone:  " + ((d.bid > d.pp && d.bid < d.r1) ? "BUY Zone" : ((d.bid < d.pp && d.bid > d.s1) ? "SELL Zone" : "Neutral")) + "\n";

      text += "--- RSI DIVERGENCE -------------\n";
      text += "Signal:      " + (d.divBull ? "BULL" : (d.divBear ? "BEAR" : "None")) + "\n\n";

      text += "--- RISK MANAGEMENT ------------\n";
      text += "Loss Streak: " + IntegerToString(losses) + "\n";

      Comment(text);
   }
};

CVisuals     *Graphics;
CStrategy    *Strategy;

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   hRSI = iRSI(_Symbol, PERIOD_CURRENT, InpRSI_Period, PRICE_CLOSE);
   if(hRSI == INVALID_HANDLE) return(INIT_FAILED);

   trade.SetExpertMagicNumber(magicNum);
   trade.SetDeviationInPoints(InpSlippage);

   Risk     = new CRiskManager();
   Graphics = new CVisuals();
   Strategy = new CStrategy();

   Graphics->SetupChartColors();
   Graphics->DrawPivots();
   if(InpShowBranding) Graphics->DrawBranding();

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(CheckPointer(Risk) == POINTER_DYNAMIC) delete Risk;
   if(CheckPointer(Graphics) == POINTER_DYNAMIC) delete Graphics;
   if(CheckPointer(Strategy) == POINTER_DYNAMIC) delete Strategy;
   ObjectsDeleteAll(0, "DGT");
   ObjectDelete(0, "MannaBrandLogo");
   Comment("");
   IndicatorRelease(hRSI);
}

void OnTick()
{
   static datetime lastDayTime = 0;
   datetime currentDay = iTime(_Symbol, PERIOD_D1, 0);

   // 1. Redraw Pivots on New Day
   if(lastDayTime != currentDay) {
      Graphics->DrawPivots();
      lastDayTime = currentDay;
   }

   // 2. Check End of Day Closure
   if(InpCloseAtDayEnd) CheckEndOfDay();

   // 3. Run Strategy
   Strategy->RunLogic();

   // 4. Update Dashboard
   if(InpShowBranding) Graphics->UpdateDashboard(Strategy->GetData());
}

//+------------------------------------------------------------------+
//| End of Day Logic                                                 |
//+------------------------------------------------------------------+
void CheckEndOfDay()
{
   MqlDateTime dt;
   TimeCurrent(dt);

   if(dt.hour == InpCloseHour && dt.min >= InpCloseMinute)
   {
      if(PositionsTotal() > 0) {
         CloseAllPositions();
      }
   }
}

void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == magicNum && PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            trade.PositionClose(ticket);
         }
      }
   }
}
