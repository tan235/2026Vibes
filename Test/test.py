import streamlit as st
import yfinance as yf
import pandas as pd
import plotly.graph_objects as go
from plotly.subplots import make_subplots

# --- CONFIGURATION ---
st.set_page_config(page_title="Manna Mindset Trader", layout="wide")
st.title("🚀 Manna Mindset: Live Trading Dashboard")

# --- SIDEBAR ---
st.sidebar.header("Settings")
ticker = st.sidebar.text_input("Ticker Symbol", value="BTC-USD")
period = st.sidebar.selectbox("Time Period", ["1mo", "3mo", "6mo", "1y"])

# --- MAIN LOGIC ---
try:
    # 1. Download Data
    with st.spinner(f"Downloading data for {ticker}..."):
        df = yf.download(ticker, period=period, interval="1d", auto_adjust=True)
    
    # 2. Fix the "MultiIndex" Bug (The Cloud often needs this)
    if isinstance(df.columns, pd.MultiIndex):
        df.columns = df.columns.get_level_values(0)

    # 3. Check if data is empty
    if df.empty:
        st.error(f"❌ No data found for '{ticker}'. Please check the symbol.")
        st.stop()

    # 4. Calculate Indicators (RSI + SMA)
    df['SMA_20'] = df['Close'].rolling(window=20).mean()
    
    delta = df['Close'].diff()
    gain = (delta.where(delta > 0, 0)).rolling(window=14).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(window=14).mean()
    rs = gain / loss
    df['RSI'] = 100 - (100 / (1 + rs))

    # 5. Display Metrics
    last_close = df['Close'].iloc[-1]
    last_rsi = df['RSI'].iloc[-1]

    col1, col2, col3 = st.columns(3)
    col1.metric("Current Price", f"${last_close:,.2f}")
    col2.metric("RSI Level", f"{last_rsi:.2f}")

    if last_rsi < 30:
        col3.success("BOLD SIGNAL: BUY 🟢")
    elif last_rsi > 70:
        col3.error("BOLD SIGNAL: SELL 🔴")
    else:
        col3.info("SIGNAL: NEUTRAL ⚪")

    # 6. Plot Interactive Chart
    fig = make_subplots(rows=2, cols=1, shared_xaxes=True, 
                        vertical_spacing=0.1, row_heights=[0.7, 0.3])

    # Candlestick
    fig.add_trace(go.Candlestick(x=df.index,
                                 open=df['Open'], high=df['High'],
                                 low=df['Low'], close=df['Close'],
                                 name='Price'), row=1, col=1)
    
    # SMA Line
    fig.add_trace(go.Scatter(x=df.index, y=df['SMA_20'], 
                             line=dict(color='orange', width=1), 
                             name='SMA 20'), row=1, col=1)

    # RSI Line
    fig.add_trace(go.Scatter(x=df.index, y=df['RSI'], 
                             line=dict(color='purple', width=2), 
                             name='RSI'), row=2, col=1)
    
    # RSI Zones
    fig.add_hline(y=70, line_dash="dash", line_color="red", row=2, col=1)
    fig.add_hline(y=30, line_dash="dash", line_color="green", row=2, col=1)

    fig.update_layout(height=600, xaxis_rangeslider_visible=False, template="plotly_dark")
    st.plotly_chart(fig, use_container_width=True)

except Exception as e:
    st.error(f"⚠️ An error occurred: {e}")