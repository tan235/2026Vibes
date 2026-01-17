import streamlit as st
import pandas as pd
import matplotlib.pyplot as plt

# --- Page Config ---
st.set_page_config(page_title="Strategize Your Life", layout="wide")

st.title("📊 Strategize Your Life: The Assessment")
st.markdown("Use this tool to map your **16 Strategic Life Units** and see where you are winning vs. losing.")

# --- Sidebar Inputs ---
st.sidebar.header("Enter Your Data")
units = [
    "1. Significant Other", "2. Family", "3. Friendship",
    "4. Physical Health", "5. Mental Health", "6. Spirituality/Faith",
    "7. Job & Career", "8. Education/Learning", "9. Finances",
    "10. Community", "11. Societal Engagement",
    "12. Hobbies", "13. Online Entertainment", "14. Offline Entertainment",
    "15. Physiological Needs", "16. Maintenance/Chores"
]

data = []
total_hours = 0

for unit in units:
    clean_name = unit.split(". ")[1]
    with st.sidebar.expander(clean_name, expanded=False):
        imp = st.slider(f"{clean_name} - Importance", 0, 10, 5)
        sat = st.slider(f"{clean_name} - Satisfaction", 0, 10, 5)
        hrs = st.number_input(f"{clean_name} - Hours/Week", 0, 168, 5)
        data.append({"Unit": clean_name, "Importance": imp, "Satisfaction": sat, "Hours": hrs})
        total_hours += hrs

st.sidebar.markdown("---")
if total_hours > 168:
    st.sidebar.error(f"⚠️ Total Hours: {total_hours}/168 (Over limit!)")
else:
    st.sidebar.success(f"✅ Total Hours: {total_hours}/168")

# --- Main Graph ---
if data:
    df = pd.DataFrame(data).sort_values("Hours", ascending=False)
    
    st.subheader("Your Strategic Life Matrix")
    
    fig, ax = plt.subplots(figsize=(10, 8))
    
    # Bubble Chart
    sizes = df["Hours"] * 200  # Scale bubbles
    scatter = ax.scatter(df["Satisfaction"], df["Importance"], s=sizes, alpha=0.6, 
                         c=df["Satisfaction"], cmap="RdYlGn", edgecolors="black", vmin=0, vmax=10)
    
    # Quadrants
    ax.axhline(5, color='gray', linestyle='--')
    ax.axvline(5, color='gray', linestyle='--')
    
    # Labels
    ax.text(0.5, 9.8, 'URGENT', color='red', fontweight='bold')
    ax.text(9.5, 9.8, 'FULFILLMENT', color='green', fontweight='bold', ha='right')
    
    # Bubble Labels
    for _, row in df.iterrows():
        if row["Hours"] > 0:
            ax.text(row["Satisfaction"], row["Importance"], 
                    f"{row['Unit']}\n({int(row['Hours'])}h)", 
                    ha='center', va='center', fontsize=8, fontweight='bold')

    ax.set_xlabel("Satisfaction")
    ax.set_ylabel("Importance")
    ax.set_xlim(-0.5, 10.5)
    ax.set_ylim(-0.5, 10.5)
    ax.grid(True, alpha=0.3)
    
    st.pyplot(fig)