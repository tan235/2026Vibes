//+------------------------------------------------------------------+
//|                                   2026 Trading Bot.mq5           |
//|                                      Manna Mindset Tools         |
//+------------------------------------------------------------------+
#property copyright "Manna Mindset"
#property version   "1.00"
#property strict

// INCLUDE TRADING LIBRARY
#include <Trade/Trade.mqh>

//==================================================================
//                        INPUT SETTINGS
//==================================================================

//--- 1. TRADING SETTINGS
input group "--- TRADING STRATEGY ---"
input bool   EnableTrading = true;       // Enable Auto-Trading?
input double RiskPercent   = 1.0;        // Base Risk % (Resets to this after a win)
input int    StopLossPts   = 200;        // Stop Loss in Points
input int    TakeProfitPts = 400;        // Take Profit in Points
input int    Slippage      = 3;          // Max Slippage allowed

//--- 2. PIVOT POINT SETTINGS
input group "--- PIVOT SETTINGS ---"
input color ColorPP = clrWhite;      // Pivot Point Color
input color ColorR  = clrLimeGreen;  // Resistance Color
input color ColorS  = clrTomato;     // Support Color

//--- 3. FILTER VISUALS
input group "--- FILTER VISUALS ---"
input bool  ShowDaily200 = true;
input bool  ShowMA50     = true;
input bool  ShowMA100    = true;
input bool  ShowMA200    = true;
input bool  ShowVWAP     = true;

//--- 4. CHART & BRANDING
input group "--- CHART & BRANDING ---"
input bool   CleanOnLoad = true;
input color  ClrBack     = clrBlack;
input color  ClrCandleUp = clrLimeGreen;
input color  ClrCandleDn = clrTomato;
input bool   ShowBranding= true;

//==================================================================
//                        GLOBAL VARIABLES
//==================================================================
CTrade   trade;
int      handleMaDaily;
int      handleMa50, handleMa100, handleMa200;
datetime lastBarTime = 0;
datetime lastDayTime = 0;
int      MAGIC_NUM = 888; // Defines which trades belong to this EA

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   handleMaDaily = iMA(_Symbol, PERIOD_D1, 200, 0, MODE_SMA, PRICE_CLOSE);
   handleMa50    = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_SMA, PRICE_CLOSE);
   handleMa100   = iMA(_Symbol, PERIOD_CURRENT, 100, 0, MODE_SMA, PRICE_CLOSE);
   handleMa200   = iMA(_Symbol, PERIOD_CURRENT, 200, 0, MODE_SMA, PRICE_CLOSE);

   trade.SetExpertMagicNumber(MAGIC_NUM);
   trade.SetDeviationInPoints(Slippage);

   if(CleanOnLoad) SetupChart();
   DrawPivots();
   if(ShowBranding) DrawBrandingLabel();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "DGT");
   ObjectsDeleteAll(0, "FLT");
   ObjectDelete(0, "MannaBrandLogo");
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentDay = iTime(_Symbol, PERIOD_D1, 0);
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   bool newBar = (lastBarTime != currentBarTime);

   // A. Visual Updates

   // Daily updates (Pivots, Daily MA if needed per day)
   if(lastDayTime != currentDay)
   {
      DrawPivots();
      lastDayTime = currentDay;
   }

   // Intraday Visuals
   // We update only on new bar to save resources, or current bar live?
   // Strategy: Full redraw on new bar. Update index 0 on every tick.
   // For simplicity and "Fixing" the heavy load, we will redraw only on new bar
   // AND update the current forming bar (index 0) on every tick.

   if(ShowDaily200) DrawDailyMA(); else ObjectsDeleteAll(0, "FLT_Daily200");

   if(ShowVWAP)     DrawVWAP(newBar);    else ObjectsDeleteAll(0, "FLT_VWAP_");
   DrawChartMAs(newBar);

   lastBarTime = currentBarTime;

   // B. Run Trading Logic
   ProcessTradingLogic();
}

//==================================================================
//                     TRADING LOGIC ENGINE
//==================================================================

void ProcessTradingLogic()
{
   double ma50[], ma100[], ma200[], maD1[];

   if(CopyBuffer(handleMa50, 0, 0, 1, ma50) <= 0) return;
   if(CopyBuffer(handleMa100, 0, 0, 1, ma100) <= 0) return;
   if(CopyBuffer(handleMa200, 0, 0, 1, ma200) <= 0) return;
   if(CopyBuffer(handleMaDaily, 0, 0, 2, maD1) <= 0) return;
   ArraySetAsSeries(maD1, true);

   double highD1 = iHigh(_Symbol, PERIOD_D1, 1);
   double lowD1 = iLow(_Symbol, PERIOD_D1, 1);
   double closeD1 = iClose(_Symbol, PERIOD_D1, 1);
   double pp = (highD1 + lowD1 + closeD1) / 3.0;
   double r1 = 2 * pp - lowD1;
   double s1 = 2 * pp - highD1;

   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double vwap = GetCurrentVWAP();
   double dailyMAValue = maD1[0];

   // Trend Definitions
   bool stackBull = (ma50[0] > ma100[0] && ma100[0] > ma200[0]);
   bool stackBear = (ma50[0] < ma100[0] && ma100[0] < ma200[0]);

   bool isStrongBull = (stackBull && bid > ma50[0] && bid > dailyMAValue && bid > vwap && bid > pp);
   bool isStrongBear = (stackBear && bid < ma50[0] && bid < dailyMAValue && bid < pp);

   // Triggers
   bool buySignal  = (isStrongBull && bid > r1);
   bool sellSignal = (isStrongBear && bid < s1);

   // --- EXECUTE TRADES ---
   if(EnableTrading && PositionsTotal() == 0)
   {
      // Get Loss Streak
      int losses = GetConsecutiveLosses();
      double currentLotSize = CalculateDefensiveLots(StopLossPts, losses);

      if(buySignal)
         trade.Buy(currentLotSize, _Symbol, ask, bid - StopLossPts*_Point, bid + TakeProfitPts*_Point, "Manna Bull");
      else if(sellSignal)
         trade.Sell(currentLotSize, _Symbol, bid, ask + StopLossPts*_Point, ask - TakeProfitPts*_Point, "Manna Bear");
   }

   // Update Dashboard
   UpdateDashboard(isStrongBull, isStrongBear, buySignal, sellSignal, r1, s1, pp, vwap, bid);
}

//+------------------------------------------------------------------+
//| DEFENSIVE RISK: Halve risk on every consecutive loss             |
//+------------------------------------------------------------------+
double CalculateDefensiveLots(int slPoints, int consecutiveLosses)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   // LOGIC: Divide Risk by 2 for every loss (Risk / 2^losses)
   // Example: 1 Loss -> 1.0% / 2 = 0.5%
   // Example: 2 Loss -> 1.0% / 4 = 0.25%
   double riskFactor = MathPow(2, consecutiveLosses);
   double adjustedRiskPercent = RiskPercent / riskFactor;

   double riskMoney = balance * (adjustedRiskPercent / 100.0);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickValue == 0) tickValue = 1.0;
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   double rawLots = riskMoney / (slPoints * tickValue);
   double lots    = MathFloor(rawLots / lotStep) * lotStep;

   double minLots = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLots = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(lots < minLots) lots = minLots; // Never go below min lots
   if(lots > maxLots) lots = maxLots;

   return lots;
}

//+------------------------------------------------------------------+
//| HELPER: Count Consecutive Losses from History                    |
//+------------------------------------------------------------------+
int GetConsecutiveLosses()
{
   // Only select necessary history if possible, but we need to find the last win.
   // Scanning all history is safe but slow.
   if(!HistorySelect(0, TimeCurrent())) return 0;

   int total = HistoryDealsTotal();
   int losses = 0;

   // Loop BACKWARDS from newest to oldest
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0)
      {
         // Check if deal matches this EA (Magic Number) and Symbol
         long dealMagic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
         string dealSymbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
         long dealEntry = HistoryDealGetInteger(ticket, DEAL_ENTRY);

         if(dealMagic == MAGIC_NUM && dealSymbol == _Symbol && dealEntry == DEAL_ENTRY_OUT) // Entry Out = Close
         {
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);

            if(profit < 0) losses++;       // Found a loss, add to streak
            else if(profit > 0) break;     // Found a win, STOP counting (streak ended)
         }
      }
   }
   return losses;
}

//==================================================================
//                     HELPERS & DRAWINGS
//==================================================================

void UpdateDashboard(bool bull, bool bear, bool buy, bool sell, double r1, double s1, double pp, double vwap, double bid)
{
   int losses = GetConsecutiveLosses();
   double currentRisk = RiskPercent / MathPow(2, losses);

   string trendStatus = "--- WAITING ---";
   if(bull) trendStatus = ">> BULLISH (Wait R1) <<";
   if(bear) trendStatus = "<< BEARISH (Wait S1) >>";
   if(buy)  trendStatus = "!!! BUY TRIGGER !!!";
   if(sell) trendStatus = "!!! SELL TRIGGER !!!";

   string text = "================================\n";
   text += "   2026 TRADING BOT (v1.0)      \n";
   text += "================================\n";
   text += "STATUS: " + trendStatus + "\n";
   text += "\n";
   text += "--- RISK MANAGEMENT ------------\n";
   text += "Consecutive Losses: " + IntegerToString(losses) + "\n";
   text += "Current Risk:       " + DoubleToString(currentRisk, 2) + "%\n";
   text += "\n";
   text += "--- ENTRY TRIGGERS -------------\n";
   text += "BUY Trigger (R1): " + DoubleToString(r1, _Digits) + "\n";
   text += "SELL Trigger (S1): " + DoubleToString(s1, _Digits) + "\n";
   text += "\n";
   text += "--- CURRENT LEVELS -------------\n";
   text += "Bid Price:   " + DoubleToString(bid, _Digits) + "\n";
   text += "Daily VWAP:  " + DoubleToString(vwap, _Digits) + "\n";
   text += "Pivot Point: " + DoubleToString(pp, _Digits) + "\n";

   Comment(text);
}

void DrawBrandingLabel()
{
   string objName = "MannaBrandLogo";
   if(ObjectFind(0, objName) < 0) ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, objName, OBJPROP_TEXT, "MANNA MINDSET");
   ObjectSetString(0, objName, OBJPROP_FONT, "Impact");
   ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 18);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, clrGold);
   ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, 350);
   ChartRedraw(0);
}

double GetCurrentVWAP() {
   int startBar = iBarShift(_Symbol, PERIOD_CURRENT, iTime(_Symbol, PERIOD_D1, 0));
   int limit = startBar;
   double cumPV = 0, cumVol = 0;
   double high[], low[], close[];
   long vol[];

   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(vol, true);

   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, limit+1, high)<=0) return 0;
   if(CopyLow(_Symbol, PERIOD_CURRENT, 0, limit+1, low)<=0) return 0;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, limit+1, close)<=0) return 0;
   if(CopyTickVolume(_Symbol, PERIOD_CURRENT, 0, limit+1, vol)<=0) return 0;

   for(int i=limit; i>=0; i--) {
      double tp=(high[i]+low[i]+close[i])/3.0;
      double v=(double)vol[i];
      cumPV+=tp*v;
      cumVol+=v;
   }
   if(cumVol>0) return cumPV/cumVol;
   return 0;
}

void DrawChartMAs(bool fullRedraw) {
   if(ShowMA50) DrawSingleMA(handleMa50, 50, clrAqua, "MA50", fullRedraw); else ObjectsDeleteAll(0, "FLT_MA50_");
   if(ShowMA100) DrawSingleMA(handleMa100, 100, clrOrange, "MA100", fullRedraw); else ObjectsDeleteAll(0, "FLT_MA100_");
   if(ShowMA200) DrawSingleMA(handleMa200, 200, clrRed, "MA200", fullRedraw); else ObjectsDeleteAll(0, "FLT_MA200_");
}

void DrawSingleMA(int handle, int period, color col, string suffix, bool fullRedraw) {
   int drawBars = 300;
   double buff[];

   // If not full redraw, we only need a few bars to update the head.
   // But we still need correct indexing.
   // Simplest robust way: always get data, but only loop 0 if not fullRedraw.

   if(CopyBuffer(handle, 0, 0, drawBars+1, buff)<=0) return;
   ArraySetAsSeries(buff, true);

   int limit = fullRedraw ? drawBars : 1;
   // Note: We always update index 0 (current bar).
   // If fullRedraw=false, we only loop i=0.

   for(int i=0; i<limit; i++) {
      string n="FLT_"+suffix+"_"+IntegerToString(i);
      datetime t1=iTime(_Symbol, PERIOD_CURRENT, i+1);
      datetime t2=iTime(_Symbol, PERIOD_CURRENT, i);
      double p1=buff[i+1];
      double p2=buff[i];

      if(p1==0||p2==0) continue;

      if(ObjectFind(0, n)<0)
         ObjectCreate(0, n, OBJ_TREND, 0, t1, p1, t2, p2);
      else {
         ObjectSetDouble(0, n, OBJPROP_PRICE, 0, p1);
         ObjectSetInteger(0, n, OBJPROP_TIME, 0, t1);
         ObjectSetDouble(0, n, OBJPROP_PRICE, 1, p2);
         ObjectSetInteger(0, n, OBJPROP_TIME, 1, t2);
      }
      ObjectSetInteger(0, n, OBJPROP_COLOR, col);
      ObjectSetInteger(0, n, OBJPROP_WIDTH, (period==200)?2:1);
      ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   }
}

void DrawVWAP(bool fullRedraw) {
   int startBar=iBarShift(_Symbol, PERIOD_CURRENT, iTime(_Symbol, PERIOD_D1, 0));
   int limit=startBar;

   double cumPV=0, cumVol=0, prevVwap=0;
   datetime prevTime=0;
   double high[], low[], close[];
   long vol[];

   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(vol, true);

   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, limit+1, high)<=0) return;
   if(CopyLow(_Symbol, PERIOD_CURRENT, 0, limit+1, low)<=0) return;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, limit+1, close)<=0) return;
   if(CopyTickVolume(_Symbol, PERIOD_CURRENT, 0, limit+1, vol)<=0) return;

   // VWAP Calculation involves iteration from start of day.
   // We cannot easily skip calculation, but we can skip drawing objects for old bars.

   for(int i=limit; i>=0; i--) {
      double tp=(high[i]+low[i]+close[i])/3.0;
      double v=(double)vol[i];
      cumPV+=tp*v;
      cumVol+=v;
      double vwap=(cumVol>0)?cumPV/cumVol:tp;
      datetime t=iTime(_Symbol, PERIOD_CURRENT, i);

      // Drawing
      if(i<limit) {
         // Optimization: Only draw if fullRedraw or if i==0 (current bar)
         if(fullRedraw || i==0) {
             string n="FLT_VWAP_"+IntegerToString(i);
             if(ObjectFind(0, n)<0)
                 ObjectCreate(0, n, OBJ_TREND, 0, prevTime, prevVwap, t, vwap);
             else {
                 ObjectSetDouble(0, n, OBJPROP_PRICE, 0, prevVwap);
                 ObjectSetInteger(0, n, OBJPROP_TIME, 0, prevTime);
                 ObjectSetDouble(0, n, OBJPROP_PRICE, 1, vwap);
                 ObjectSetInteger(0, n, OBJPROP_TIME, 1, t);
             }
             ObjectSetInteger(0, n, OBJPROP_COLOR, clrHotPink);
             ObjectSetInteger(0, n, OBJPROP_STYLE, STYLE_DASHDOT);
             ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, false);
             ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
         }
      }
      prevVwap=vwap;
      prevTime=t;
   }
}

void DrawDailyMA() {
   double ma[];
   if(CopyBuffer(handleMaDaily, 0, 0, 1, ma)<=0) return;
   double p=ma[0];
   datetime t1=iTime(_Symbol, PERIOD_D1, 0);
   datetime t2=t1+PeriodSeconds(PERIOD_D1);
   string n="FLT_Daily200";

   if(ObjectFind(0, n)<0)
      ObjectCreate(0, n, OBJ_TREND, 0, t1, p, t2, p);
   else {
      ObjectSetDouble(0, n, OBJPROP_PRICE, 0, p);
      ObjectSetInteger(0, n, OBJPROP_TIME, 0, t1);
      ObjectSetDouble(0, n, OBJPROP_PRICE, 1, p);
      ObjectSetInteger(0, n, OBJPROP_TIME, 1, t2);
   }
   ObjectSetInteger(0, n, OBJPROP_COLOR, clrYellow);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, false);
   ObjectSetString(0, n, OBJPROP_TEXT, " Daily 200 SMA");
}

void DrawPivots() {
   ObjectsDeleteAll(0, "DGT");
   double h=iHigh(_Symbol, PERIOD_D1, 1);
   double l=iLow(_Symbol, PERIOD_D1, 1);
   double c=iClose(_Symbol, PERIOD_D1, 1);

   double pp=(h+l+c)/3.0;
   double r1=2*pp-l;
   double s1=2*pp-h;
   double r2=pp+(h-l);
   double s2=pp-(h-l);
   double r3=h+2*(pp-l);
   double s3=l-2*(h-pp);

   CreateLine("PP", pp, ColorPP, 2);
   CreateLine("R1", r1, ColorR, 1);
   CreateLine("S1", s1, ColorS, 1);
   CreateLine("R2", r2, ColorR, 1);
   CreateLine("S2", s2, ColorS, 1);
   CreateLine("R3", r3, ColorR, 1);
   CreateLine("S3", s3, ColorS, 1);
   ChartRedraw(0);
}

void CreateLine(string name, double price, color col, int width) {
   datetime t1=iTime(_Symbol, PERIOD_D1, 0);
   datetime t2=t1+PeriodSeconds(PERIOD_D1);
   string n="DGT "+name;

   if(ObjectFind(0, n)<0)
      ObjectCreate(0, n, OBJ_TREND, 0, t1, price, t2, price);
   else {
      ObjectSetDouble(0, n, OBJPROP_PRICE, 0, price);
      ObjectSetInteger(0, n, OBJPROP_TIME, 0, t1);
      ObjectSetDouble(0, n, OBJPROP_PRICE, 1, price);
      ObjectSetInteger(0, n, OBJPROP_TIME, 1, t2);
   }
   ObjectSetInteger(0, n, OBJPROP_COLOR, col);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, false);
   ObjectSetString(0, n, OBJPROP_TEXT, "  "+name);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
}

void SetupChart() {
   ChartSetInteger(0, CHART_MODE, CHART_CANDLES);
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   ChartSetInteger(0, CHART_SHOW_PERIOD_SEP, false);
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, ClrBack);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrWhite);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, ClrCandleDn);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, ClrCandleDn);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, ClrCandleUp);
   ChartSetInteger(0, CHART_COLOR_CHART_UP, ClrCandleUp);
   ChartRedraw(0);
}