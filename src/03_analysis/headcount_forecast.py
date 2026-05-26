"""
Enova Technologies - Headcount Forecast Model
==============================================
Pulls actual hiring and attrition data from SQL Server,
computes three forecast scenarios through end of 2025,
and writes an Excel workbook to outputs/.

Run from the project root:
    python src/03_analysis/headcount_forecast.py

Requirements:
    pip install pandas sqlalchemy pyodbc openpyxl python-dateutil
"""

import pandas as pd
import numpy as np
from sqlalchemy import create_engine, text
from datetime import date
from dateutil.relativedelta import relativedelta
import os
import warnings
warnings.filterwarnings('ignore')

# =============================================================
# CONFIGURATION
# =============================================================

SERVER      = r'DAPOLAPTOP\DAPOSQLSERVER'
DATABASE    = 'enova_talent'
OUTPUT_PATH = r'outputs\headcount_forecast.xlsx'

FORECAST_START          = date(2025, 6, 1)
FORECAST_END            = date(2025, 12, 31)
TODAY                   = date(2025, 7, 1)
HC_TARGET               = 500
VELOCITY_LOOKBACK_MONTHS = 6

# =============================================================
# CONNECTION
# =============================================================

def get_engine():
    conn_str = (
        f'mssql+pyodbc://{SERVER}/{DATABASE}'
        f'?driver=ODBC+Driver+17+for+SQL+Server'
        f'&trusted_connection=yes'
    )
    return create_engine(conn_str)


# =============================================================
# PULL DATA
# =============================================================

def pull_data(engine) -> dict:
    print('Pulling data from SQL Server...')

    with engine.connect() as conn:

        hc_by_dept = pd.read_sql(text("""
            SELECT
                department,
                COUNT(*) AS current_headcount
            FROM silver.employees
            WHERE status = 'active'
            GROUP BY department
            ORDER BY current_headcount DESC
        """), conn)

        total_hc = pd.read_sql(text("""
            SELECT COUNT(*) AS total
            FROM silver.employees
            WHERE status = 'active'
        """), conn).iloc[0]['total']

        monthly_hires = pd.read_sql(text(f"""
            SELECT
                FORMAT(hired_date, 'yyyy-MM') AS month,
                department,
                COUNT(*) AS hires
            FROM gold.fact_applications
            WHERE hired = 1
              AND hired_date >= DATEADD(
                    MONTH, -{VELOCITY_LOOKBACK_MONTHS},
                    CAST('{TODAY}' AS DATE))
              AND hired_date < CAST('{TODAY}' AS DATE)
            GROUP BY FORMAT(hired_date, 'yyyy-MM'), department
            ORDER BY month
        """), conn)

        monthly_attrition = pd.read_sql(text(f"""
            SELECT
                FORMAT(termination_date, 'yyyy-MM') AS month,
                department,
                termination_reason,
                COUNT(*) AS terminations
            FROM silver.employees
            WHERE status = 'terminated'
              AND termination_date >= DATEADD(
                    MONTH, -{VELOCITY_LOOKBACK_MONTHS},
                    CAST('{TODAY}' AS DATE))
              AND termination_date < CAST('{TODAY}' AS DATE)
            GROUP BY FORMAT(termination_date, 'yyyy-MM'),
                     department, termination_reason
            ORDER BY month
        """), conn)

        open_reqs = pd.read_sql(text("""
            SELECT
                department,
                COUNT(*) AS open_reqs,
                SUM(headcount_approved) AS open_headcount
            FROM silver.jobs
            WHERE status = 'open'
            GROUP BY department
        """), conn)

        hc_plan = pd.read_sql(text("""
            SELECT
                finance_department AS department,
                quarter,
                headcount_total_approved,
                headcount_actual
            FROM gold.fact_headcount
            WHERE quarter IN ('Q3_2025', 'Q4_2025')
            ORDER BY finance_department, quarter
        """), conn)

        tth_by_dept = pd.read_sql(text("""
            SELECT
                department,
                AVG(days_to_hire)  AS avg_days_to_hire,
                COUNT(*)           AS n_hires
            FROM gold.fact_applications
            WHERE hired = 1
              AND days_to_hire IS NOT NULL
              AND days_to_hire > 0
              AND days_to_hire < 365
            GROUP BY department
            ORDER BY avg_days_to_hire DESC
        """), conn)

    print(f'  Current headcount:      {total_hc}')
    print(f'  Departments:            {len(hc_by_dept)}')
    print(f'  Monthly hire records:   {len(monthly_hires)}')
    print(f'  Monthly attrition recs: {len(monthly_attrition)}')
    print(f'  Open requisitions:      {open_reqs["open_reqs"].sum()} '
          f'({open_reqs["open_headcount"].sum()} heads)')

    return {
        'hc_by_dept':        hc_by_dept,
        'total_hc':          int(total_hc),
        'monthly_hires':     monthly_hires,
        'monthly_attrition': monthly_attrition,
        'open_reqs':         open_reqs,
        'hc_plan':           hc_plan,
        'tth_by_dept':       tth_by_dept,
    }


# =============================================================
# COMPUTE VELOCITY
# =============================================================

def compute_velocity(data: dict) -> dict:
    hires     = data['monthly_hires']
    attrition = data['monthly_attrition']

    avg_monthly_hires = (
        hires.groupby('month')['hires'].sum().mean()
        if not hires.empty else 0
    )
    avg_monthly_attrition = (
        attrition.groupby('month')['terminations'].sum().mean()
        if not attrition.empty else 0
    )

    dept_map = {
        'Engineering': 'Technology',
        'Product':     'Product',
        'Analytics':   'Data and Analytics',
        'Growth':      'Commercial',
        'Finance':     'Finance',
        'Operations':  'Operations',
        'HR':          'People',
        'Legal':       'Legal and Compliance',
    }

    dept_hires = (
        hires.groupby('department')['hires']
        .sum()
        .div(VELOCITY_LOOKBACK_MONTHS)
        .reset_index()
        .rename(columns={'hires': 'avg_monthly_hires'})
    )
    dept_hires['department_display'] = dept_hires['department'].map(
        lambda x: dept_map.get(x, x))

    dept_attrition = (
        attrition.groupby('department')['terminations']
        .sum()
        .div(VELOCITY_LOOKBACK_MONTHS)
        .reset_index()
        .rename(columns={'terminations': 'avg_monthly_attrition'})
    )

    print(f'\nVelocity (avg/month over last {VELOCITY_LOOKBACK_MONTHS} months):')
    print(f'  Hires:      {avg_monthly_hires:.1f}')
    print(f'  Attrition:  {avg_monthly_attrition:.1f}')
    print(f'  Net growth: {avg_monthly_hires - avg_monthly_attrition:.1f}')

    return {
        'avg_monthly_hires':     avg_monthly_hires,
        'avg_monthly_attrition': avg_monthly_attrition,
        'net_monthly_growth':    avg_monthly_hires - avg_monthly_attrition,
        'dept_hires':            dept_hires,
        'dept_attrition':        dept_attrition,
    }


# =============================================================
# BUILD FORECAST
# =============================================================

def build_monthly_forecast(
    start_hc: int,
    monthly_hires: float,
    monthly_attrition: float,
    months: list,
    scenario_name: str
) -> pd.DataFrame:
    rows = []
    current_hc = start_hc

    for m in months:
        projected_hc  = current_hc + monthly_hires - monthly_attrition
        gap_to_target = HC_TARGET - projected_hc

        rows.append({
            'Month':               m.strftime('%b %Y'),
            'month_date':          m,
            'Scenario':            scenario_name,
            'Opening HC':          round(current_hc),
            'Projected hires':     round(monthly_hires, 1),
            'Projected attrition': round(monthly_attrition, 1),
            'Closing HC':          round(projected_hc),
            'Gap to target':       round(gap_to_target),
            '% of target':         round(projected_hc / HC_TARGET * 100, 1),
        })

        current_hc = projected_hc

    return pd.DataFrame(rows)


def run_all_scenarios(data: dict, velocity: dict) -> dict:
    base_hires     = velocity['avg_monthly_hires']
    base_attrition = velocity['avg_monthly_attrition']
    start_hc       = data['total_hc']

    months = []
    m = FORECAST_START
    while m <= FORECAST_END:
        months.append(m)
        m = m + relativedelta(months=1)

    print(f'\nForecast months: {[m.strftime("%b %Y") for m in months]}')

    scenarios = {
        'Base case': build_monthly_forecast(
            start_hc, base_hires, base_attrition,
            months, 'Base case'),

        'Optimistic': build_monthly_forecast(
            start_hc,
            base_hires * 1.20,
            base_attrition * 0.90,
            months, 'Optimistic'),

        'Pessimistic': build_monthly_forecast(
            start_hc,
            base_hires * 0.85,
            base_attrition * 1.20,
            months, 'Pessimistic'),
    }

    for name, df in scenarios.items():
        final = df.iloc[-1]
        print(f'\n  {name}:')
        print(f'    Year-end headcount: {final["Closing HC"]}')
        print(f'    Gap to {HC_TARGET} target: {final["Gap to target"]}')
        print(f'    % of target: {final["% of target"]}%')

    return scenarios


def build_dept_forecast(data: dict, velocity: dict) -> pd.DataFrame:
    dept_hc    = data['hc_by_dept'].set_index('department')
    dept_hires = velocity['dept_hires'].set_index('department')
    dept_att   = velocity['dept_attrition'].set_index('department')
    open_reqs  = data['open_reqs'].set_index('department')

    dept_map = {
        'Engineering': 'Technology',
        'Product':     'Product',
        'Analytics':   'Data and Analytics',
        'Growth':      'Commercial',
        'Finance':     'Finance',
        'Operations':  'Operations',
        'HR':          'People',
        'Legal':       'Legal and Compliance',
    }

    months_remaining = len(pd.date_range(
        FORECAST_START, FORECAST_END, freq='MS'))

    rows = []
    for dept_hris, row in dept_hc.iterrows():
        current  = int(row['current_headcount'])
        m_hires  = float(dept_hires.loc[dept_hris, 'avg_monthly_hires']) \
            if dept_hris in dept_hires.index else 0
        m_att    = float(dept_att.loc[dept_hris, 'avg_monthly_attrition']) \
            if dept_hris in dept_att.index else 0
        open_h   = int(open_reqs.loc[dept_hris, 'open_headcount']) \
            if dept_hris in open_reqs.index else 0

        projected = round(current + (m_hires - m_att) * months_remaining)

        rows.append({
            'Department (HRIS)':     dept_hris,
            'Department':            dept_map.get(dept_hris, dept_hris),
            'Current headcount':     current,
            'Avg monthly hires':     round(m_hires, 1),
            'Avg monthly attrition': round(m_att, 1),
            'Net monthly growth':    round(m_hires - m_att, 1),
            'Open requisitions':     open_h,
            'Projected year-end':    projected,
            'Change':                projected - current,
        })

    return pd.DataFrame(rows).sort_values(
        'Current headcount', ascending=False)


# =============================================================
# WRITE EXCEL
# =============================================================

def write_excel(scenarios: dict, dept_df: pd.DataFrame,
                data: dict, velocity: dict, output_path: str):

    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    with pd.ExcelWriter(output_path, engine='openpyxl') as writer:

        # Sheet 1: Forecast — all scenarios side by side
        all_scenarios = pd.concat(scenarios.values(), ignore_index=True)

        forecast_wide = all_scenarios.pivot_table(
            index=['Month', 'month_date'],
            columns='Scenario',
            values=['Closing HC', 'Gap to target', '% of target'],
            aggfunc='first'
        ).reset_index()

        forecast_wide.columns = [
            ' - '.join(filter(None, c)).strip()
            for c in forecast_wide.columns
        ]
        forecast_wide = forecast_wide.sort_values('month_date').drop(
            columns=['month_date'])

        forecast_wide.to_excel(
            writer, sheet_name='Forecast', index=False, startrow=2)

        ws = writer.sheets['Forecast']
        ws['A1'] = 'Enova Technologies — Headcount Forecast to Dec 2025'
        ws['A2'] = (
            f'Base: current velocity | '
            f'Optimistic: +20% hires / -10% attrition | '
            f'Pessimistic: -15% hires / +20% attrition | '
            f'Target: {HC_TARGET}')

        # Sheet 2: By Department
        dept_df.to_excel(
            writer, sheet_name='By Department', index=False, startrow=2)

        ws2 = writer.sheets['By Department']
        ws2['A1'] = 'Department-level forecast — base case'
        ws2['A2'] = (
            f'Based on {VELOCITY_LOOKBACK_MONTHS}-month avg '
            f'hiring and attrition velocity')

        # Sheet 3: Assumptions
        assumptions = pd.DataFrame([
            ('Data as-of date',                str(TODAY)),
            ('Forecast start',                 str(FORECAST_START)),
            ('Forecast end',                   str(FORECAST_END)),
            ('Board headcount target',         HC_TARGET),
            ('Velocity lookback (months)',     VELOCITY_LOOKBACK_MONTHS),
            ('Current active headcount',       data['total_hc']),
            ('Avg monthly hires (base)',
             round(velocity['avg_monthly_hires'], 2)),
            ('Avg monthly attrition (base)',
             round(velocity['avg_monthly_attrition'], 2)),
            ('Net monthly growth (base)',
             round(velocity['net_monthly_growth'], 2)),
            ('Optimistic hire multiplier',     '1.20 (+20%)'),
            ('Optimistic attrition multiplier','0.90 (-10%)'),
            ('Pessimistic hire multiplier',    '0.85 (-15%)'),
            ('Pessimistic attrition multiplier','1.20 (+20%)'),
            ('Data source',
             f'{DATABASE} — gold.fact_applications, silver.employees'),
            ('Script', 'src/03_analysis/headcount_forecast.py'),
        ], columns=['Assumption', 'Value'])

        assumptions.to_excel(
            writer, sheet_name='Assumptions', index=False, startrow=2)

        ws3 = writer.sheets['Assumptions']
        ws3['A1'] = 'Forecast assumptions and data sources'
        ws3['A2'] = (
            'All inputs derived from actual SQL Server data. '
            'Adjust multipliers above to rerun scenarios.')

        # Column widths
        for sheet_name in writer.sheets:
            ws_fmt = writer.sheets[sheet_name]
            for col in ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I']:
                ws_fmt.column_dimensions[col].width = 22

    print(f'\nExcel saved to: {output_path}')


# =============================================================
# MAIN
# =============================================================

def main():
    print('=' * 55)
    print('ENOVA TECHNOLOGIES — HEADCOUNT FORECAST')
    print('=' * 55)

    engine = get_engine()
    print('Connected to SQL Server.')

    data      = pull_data(engine)
    velocity  = compute_velocity(data)
    scenarios = run_all_scenarios(data, velocity)
    dept_df   = build_dept_forecast(data, velocity)

    write_excel(scenarios, dept_df, data, velocity, OUTPUT_PATH)

    base_final = scenarios['Base case'].iloc[-1]
    opt_final  = scenarios['Optimistic'].iloc[-1]
    pes_final  = scenarios['Pessimistic'].iloc[-1]

    months_remaining = len(pd.date_range(
        FORECAST_START, FORECAST_END, freq='MS'))
    hires_needed = (HC_TARGET - data['total_hc']) / months_remaining

    print('\n' + '=' * 55)
    print('FORECAST SUMMARY')
    print('=' * 55)
    print(f'\nCurrent headcount:     {data["total_hc"]}')
    print(f'Board target:          {HC_TARGET} by {FORECAST_END.strftime("%b %Y")}')
    print(f'Gap to close:          {HC_TARGET - data["total_hc"]} heads')
    print(f'Months remaining:      {months_remaining}')
    print(f'\nBase case year-end:    {base_final["Closing HC"]} '
          f'({base_final["% of target"]}% of target, '
          f'gap: {base_final["Gap to target"]})')
    print(f'Optimistic year-end:   {opt_final["Closing HC"]} '
          f'({opt_final["% of target"]}% of target, '
          f'gap: {opt_final["Gap to target"]})')
    print(f'Pessimistic year-end:  {pes_final["Closing HC"]} '
          f'({pes_final["% of target"]}% of target, '
          f'gap: {pes_final["Gap to target"]})')
    print(f'\nRequired monthly hires to hit target: {hires_needed:.1f}')
    print(f'Current monthly hires:                '
          f'{velocity["avg_monthly_hires"]:.1f}')
    print(f'Hiring gap:                           '
          f'{hires_needed - velocity["avg_monthly_hires"]:.1f} additional '
          f'hires/month needed')
    print(f'\nOutput: {OUTPUT_PATH}')


if __name__ == '__main__':
    main()