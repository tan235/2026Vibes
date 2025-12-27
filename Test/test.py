import streamlit as st
import yfinance as yf
import pandas as pd
import matplotlib.pyplot as plt

# 1. TITLE AND SIDEBAR
st.set_page_config(page_title="Manna Mindset Trader", layout="wide")
st.title("🚀 Manna Mindset: AI Trading Dashboard")

# Create a sidebar for user input
st.sidebar.header("User Input")
ticker = st.sidebar.text_input("Enter Ticker Symbol", value="BTC-USD")
period = st.sidebar.selectbox("Select Time Period", ["1mo", "3mo", "6mo", "1y", "5y"])

# 2. FETCH DATA FUNCTION
def load_data(symbol, time_period):
    st.write(f"Downloading data for: **{symbol}**...")
    data = yf.download(symbol, period=time_period, interval="1d", auto_adjust=True)
    
    # Flatten MultiIndex columns if necessary (The Fix we learned)
    if isinstance(data.columns, pd.MultiIndex):
        data.columns = data.columns.get_level_values(0)
        
    return data

# Load the data
try:
    df = load_data(ticker, period)

    # 3. CALCULATE INDICATORS (RSI)
    delta = df['Close'].diff()
    gain = (delta.where(delta > 0, 0)).rolling(window=14).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(window=14).mean()
    rs = gain / loss
    df['RSI'] = 100 - (100 / (1 + rs))

    # 4. DISPLAY LATEST STATS
    latest_price = df['Close'].iloc[-1]
    latest_rsi = df['RSI'].iloc[-1]
    
    # Create columns for nice layout
    col1, col2, col3 = st.columns(3)
    col1.metric("Current Price", f"${latest_price:,.2f}")
    col2.metric("RSI Level", f"{latest_rsi:.2f}")

    # Display Dynamic Signal
    if latest_rsi < 30:
        col3.error("SIGNAL: BUY (Oversold) 🟢") # Green/Red inverse in trading context, keeping simple
    elif latest_rsi > 70:
        col3.error("SIGNAL: SELL (Overbought) 🔴")
    else:
        col3.info("SIGNAL: NEUTRAL ⚪")

    # 5. CHARTS
    st.subheader("Price & Indicator Analysis")
    
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 8), sharex=True)
    
    # Price
    ax1.plot(df.index, df['Close'], label='Price')
    ax1.set_title(f'{ticker} Price')
    ax1.grid(True)
    
    # RSI
    ax2.plot(df.index, df['RSI'], label='RSI', color='purple')
    ax2.axhline(70, color='red', linestyle='--')
    ax2.axhline(30, color='green', linestyle='--')
    ax2.set_title('RSI Indicator')
    ax2.grid(True)
    
    # Show the plot in Streamlit
    st.pyplot(fig)

    # 6. SHOW DATA TABLE
    if st.checkbox("Show Raw Data"):
        st.dataframe(df.tail(10))

except Exception as e:
    st.error(f"Error loading data: {e}. Please check the ticker symbol.")