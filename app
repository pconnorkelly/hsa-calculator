import streamlit as st
import pandas as pd
import plotly.graph_objects as go


# ============================================================
# PAGE CONFIG
# ============================================================

st.set_page_config(
    page_title="Retirement Calculator",
    page_icon="📈",
    layout="wide",
)


# ============================================================
# HELPER FUNCTIONS
# ============================================================

def format_currency(value):
    """Format a number as US dollars."""
    return f"${value:,.0f}"


def format_compact_currency(value):
    """Format large numbers in a compact form."""
    if abs(value) >= 1_000_000:
        return f"${value / 1_000_000:.2f}M"
    elif abs(value) >= 1_000:
        return f"${value / 1_000:.0f}K"
    else:
        return f"${value:,.0f}"


def calculate_projection(
    current_age,
    current_balance,
    expected_return,
    inflation,
    periods,
    inflate_contributions,
):
    """
    Calculate year-by-year portfolio projection.

    Each period contains:
        start_age
        end_age
        contribution
        withdrawal

    Contributions are inflated annually within each period when
    inflate_contributions is True.

    Withdrawals remain at their stated nominal amount.
    """

    results = []

    balance = current_balance

    # Track how many years have elapsed since the beginning
    # of the projection for contribution inflation.
    years_elapsed = 0

    # Calculate each age individually.
    for age in range(current_age, periods[-1]["end_age"] + 1):

        # Find the applicable period.
        applicable_period = None

        for period in periods:
            if period["start_age"] <= age < period["end_age"]:
                applicable_period = period
                break

        # If we're exactly at the final end age, don't apply
        # another year's contribution/withdrawal.
        if applicable_period is None:
            break

        years_into_period = age - applicable_period["start_age"]

        base_contribution = applicable_period["contribution"]
        withdrawal = applicable_period["withdrawal"]

        if inflate_contributions:
            contribution = (
                base_contribution
                * ((1 + inflation) ** years_into_period)
            )
        else:
            contribution = base_contribution

        beginning_balance = balance

        # Contributions and withdrawals occur at the beginning
        # of the year, followed by investment growth.
        balance_before_growth = (
            beginning_balance
            + contribution
            - withdrawal
        )

        investment_growth = (
            balance_before_growth * expected_return
        )

        ending_balance = balance_before_growth + investment_growth

        # Inflation-adjusted balance in today's dollars.
        real_balance = ending_balance / (
            (1 + inflation) ** years_elapsed
        )

        results.append(
            {
                "Age": age,
                "Beginning Balance": beginning_balance,
                "Contribution": contribution,
                "Withdrawal": withdrawal,
                "Investment Growth": investment_growth,
                "Ending Balance": ending_balance,
                "Real Balance": real_balance,
            }
        )

        balance = ending_balance
        years_elapsed += 1

        # Stop if the portfolio has been depleted.
        if balance <= 0:
            balance = 0

            # Add a final zero-balance row if desired.
            break

    return pd.DataFrame(results)


# ============================================================
# TITLE
# ============================================================

st.title("📈 Retirement Calculator")

st.markdown(
    """
    Project the growth of your retirement portfolio using different
    contribution and withdrawal assumptions at different ages.
    """
)


# ============================================================
# SIDEBAR — CORE ASSUMPTIONS
# ============================================================

st.sidebar.header("Core Assumptions")

current_age = st.sidebar.slider(
    "Current age",
    min_value=18,
    max_value=80,
    value=29,
    step=1,
)

current_balance = st.sidebar.slider(
    "Current portfolio balance",
    min_value=0,
    max_value=5_000_000,
    value=100_000,
    step=5_000,
    format="$%d",
)

expected_return_pct = st.sidebar.slider(
    "Expected annual return",
    min_value=0.0,
    max_value=15.0,
    value=7.0,
    step=0.1,
    format="%.1f%%",
)

inflation_pct = st.sidebar.slider(
    "Expected inflation",
    min_value=0.0,
    max_value=10.0,
    value=2.5,
    step=0.1,
    format="%.1f%%",
)

expected_return = expected_return_pct / 100
inflation = inflation_pct / 100


# ============================================================
# CONTRIBUTION SETTINGS
# ============================================================

st.sidebar.header("Contribution Settings")

inflate_contributions = st.sidebar.checkbox(
    "Inflate annual contributions",
    value=True,
    help=(
        "When enabled, contributions increase annually based on "
        "the expected inflation rate within each time period."
    ),
)


# ============================================================
# TIME PERIODS
# ============================================================

st.sidebar.header("Time Periods")

st.sidebar.caption(
    "Create different contribution and withdrawal assumptions "
    "for different ages."
)

num_periods = st.sidebar.number_input(
    "Number of time periods",
    min_value=1,
    max_value=8,
    value=3,
    step=1,
)


# ============================================================
# PERIOD INPUTS
# ============================================================

periods = []

previous_end_age = current_age

for i in range(int(num_periods)):

    period_number = i + 1

    with st.sidebar.expander(
        f"Period {period_number}",
        expanded=(i == 0),
    ):

        # First period starts at current age.
        # Later periods start where the previous period ended.
        start_age = previous_end_age

        st.write(f"**Ages {start_age}–...**")

        # Make sure there is enough room for subsequent periods.
        min_end_age = start_age + 1

        end_age = st.slider(
            "End age",
            min_value=min_end_age,
            max_value=100,
            value=min(
                max(start_age + 10, min_end_age),
                100,
            ),
            step=1,
            key=f"end_age_{i}",
        )

        contribution = st.slider(
            "Annual contribution",
            min_value=0,
            max_value=200_000,
            value=25_000 if i == 0 else 0,
            step=1_000,
            format="$%d",
            key=f"contribution_{i}",
        )

        withdrawal = st.slider(
            "Annual withdrawal",
            min_value=0,
            max_value=300_000,
            value=0 if i < 2 else 50_000,
            step=1_000,
            format="$%d",
            key=f"withdrawal_{i}",
        )

        periods.append(
            {
                "start_age": start_age,
                "end_age": end_age,
                "contribution": contribution,
                "withdrawal": withdrawal,
            }
        )

        previous_end_age = end_age


# ============================================================
# VALIDATION
# ============================================================

valid_periods = True

for i in range(1, len(periods)):
    if periods[i]["start_age"] != periods[i - 1]["end_age"]:
        valid_periods = False


if not valid_periods:
    st.error(
        "Time periods must be consecutive. Please check your period settings."
    )
    st.stop()


# ============================================================
# CALCULATE
# ============================================================

df = calculate_projection(
    current_age=current_age,
    current_balance=current_balance,
    expected_return=expected_return,
    inflation=inflation,
    periods=periods,
    inflate_contributions=inflate_contributions,
)


# ============================================================
# SUMMARY METRICS
# ============================================================

if len(df) > 0:

    final_row = df.iloc[-1]

    final_balance = final_row["Ending Balance"]
    final_real_balance = final_row["Real Balance"]

    total_contributions = df["Contribution"].sum()
    total_withdrawals = df["Withdrawal"].sum()
    total_growth = df["Investment Growth"].sum()

    peak_balance = df["Ending Balance"].max()
    peak_age = df.loc[
        df["Ending Balance"].idxmax(),
        "Age"
    ]

    st.subheader("Projection Summary")

    col1, col2, col3, col4 = st.columns(4)

    with col1:
        st.metric(
            "Final balance",
            format_compact_currency(final_balance),
        )

    with col2:
        st.metric(
            "Final balance in today's dollars",
            format_compact_currency(final_real_balance),
        )

    with col3:
        st.metric(
            "Peak portfolio",
            format_compact_currency(peak_balance),
            f"Age {peak_age}",
        )

    with col4:
        st.metric(
            "Total contributions",
            format_compact_currency(total_contributions),
        )


# ============================================================
# PORTFOLIO GROWTH GRAPH
# ============================================================

st.subheader("Portfolio Growth")

fig = go.Figure()

fig.add_trace(
    go.Scatter(
        x=df["Age"],
        y=df["Ending Balance"],
        mode="lines",
        name="Portfolio balance",
        line=dict(width=3),
        hovertemplate=(
            "Age %{x}<br>"
            "Balance $%{y:,.0f}"
            "<extra></extra>"
        ),
    )
)

fig.add_trace(
    go.Scatter(
        x=df["Age"],
        y=df["Real Balance"],
        mode="lines",
        name="Today's dollars",
        line=dict(
            width=2,
            dash="dash",
        ),
        hovertemplate=(
            "Age %{x}<br>"
            "Today's dollars $%{y:,.0f}"
            "<extra></extra>"
        ),
    )
)

fig.update_layout(
    xaxis_title="Age",
    yaxis_title="Portfolio Value",
    hovermode="x unified",
    height=550,
    margin=dict(
        l=20,
        r=20,
        t=30,
        b=20,
    ),
    legend=dict(
        orientation="h",
        yanchor="bottom",
        y=1.02,
        xanchor="right",
        x=1,
    ),
)

fig.update_yaxes(
    tickprefix="$",
    tickformat=",.0f",
)

st.plotly_chart(
    fig,
    use_container_width=True,
)


# ============================================================
# CASH FLOW GRAPH
# ============================================================

st.subheader("Annual Contributions & Withdrawals")

cashflow_fig = go.Figure()

cashflow_fig.add_trace(
    go.Bar(
        x=df["Age"],
        y=df["Contribution"],
        name="Contributions",
        hovertemplate=(
            "Age %{x}<br>"
            "Contribution $%{y:,.0f}"
            "<extra></extra>"
        ),
    )
)

cashflow_fig.add_trace(
    go.Bar(
        x=df["Age"],
        y=-df["Withdrawal"],
        name="Withdrawals",
        hovertemplate=(
            "Age %{x}<br>"
            "Withdrawal $%{customdata:,.0f}"
            "<extra></extra>"
        ),
        customdata=df["Withdrawal"],
    )
)

cashflow_fig.update_layout(
    xaxis_title="Age",
    yaxis_title="Annual Cash Flow",
    barmode="relative",
    height=400,
    margin=dict(
        l=20,
        r=20,
        t=30,
        b=20,
    ),
)

cashflow_fig.update_yaxes(
    tickprefix="$",
    tickformat=",.0f",
)

st.plotly_chart(
    cashflow_fig,
    use_container_width=True,
)


# ============================================================
# YEAR-BY-YEAR TABLE
# ============================================================

with st.expander("View year-by-year projection"):

    display_df = df.copy()

    display_df["Beginning Balance"] = (
        display_df["Beginning Balance"].map(format_currency)
    )

    display_df["Contribution"] = (
        display_df["Contribution"].map(format_currency)
    )

    display_df["Withdrawal"] = (
        display_df["Withdrawal"].map(format_currency)
    )

    display_df["Investment Growth"] = (
        display_df["Investment Growth"].map(format_currency)
    )

    display_df["Ending Balance"] = (
        display_df["Ending Balance"].map(format_currency)
    )

    display_df["Real Balance"] = (
        display_df["Real Balance"].map(format_currency)
    )

    st.dataframe(
        display_df,
        use_container_width=True,
        hide_index=True,
    )


# ============================================================
# ASSUMPTIONS
# ============================================================

with st.expander("Calculation assumptions"):

    st.markdown(
        f"""
        **Current age:** {current_age}

        **Starting portfolio:** {format_currency(current_balance)}

        **Expected annual return:** {expected_return_pct:.1f}%

        **Expected inflation:** {inflation_pct:.1f}%

        **Contributions inflated:** {"Yes" if inflate_contributions else "No"}

        Investment growth is applied annually after that year's
        contribution and withdrawal.

        The "Today's dollars" line adjusts the projected portfolio
        for the assumed inflation rate.

        Withdrawals are kept at the nominal amount entered for each
        period. If you want withdrawals to increase with inflation,
        enter the desired withdrawal amount separately for each
        period.
        """
    )


# ============================================================
# FOOTER
# ============================================================

st.divider()

st.caption(
    "This calculator is for educational and planning purposes only "
    "and does not account for taxes, fees, Social Security, or "
    "sequence-of-returns risk."
)
