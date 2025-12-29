import streamlit as st
import yfinance as yf
import pandas as pd
import plotly.graph_objects as go
from plotly.subplots import make_subplots

st.set_page_config(layout="wide", page_title="Manna Mindset: Pro Trader")
st.title("🛡️ Manna Mindset: Institutional View")

# Sidebar
ticker = st.sidebar.text_input("Symbol", "BTC-USD")
# We need intraday data for accurate VWAP, but yfinance free is limited.
# We will use Daily data to approximate the "Yearly Anchored VWAP".
df = yf.download(ticker, period="1y", interval="1d", auto_adjust=True)

if isinstance(df.columns, pd.MultiIndex):
    df.columns = df.columns.get_level_values(0)

# CALCULATION: Anchored VWAP (Year To Date)
# Formula: Cumulative(Price * Volume) / Cumulative(Volume)
df['Typical_Price'] = (df['High'] + df['Low'] + df['Close']) / 3
df['VP'] = df['Typical_Price'] * df['Volume']
df['Total_VP'] = df['VP'].cumsum()
df['Total_Volume'] = df['Volume'].cumsum()
df['VWAP'] = df['Total_VP'] / df['Total_Volume']

# PLOTTING
fig = make_subplots(rows=1, cols=1)

# 1. Price Candles
fig.add_trace(go.Candlestick(x=df.index,
                             open=df['Open'], high=df['High'],
                             low=df['Low'], close=df['Close'],
                             name='Price'))

# 2. VWAP Line (The "Institution" Line)
fig.add_trace(go.Scatter(x=df.index, y=df['VWAP'], 
                         line=dict(color='#FFA500', width=2), 
                         name='Yearly VWAP'))

fig.update_layout(height=600, template="plotly_dark", title_text=f"{ticker} - Anchored VWAP Analysis")
st.plotly_chart(fig, use_container_width=True)