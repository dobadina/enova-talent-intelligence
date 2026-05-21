"""
Enova Technologies - Bronze Layer Load
=======================================
Loads all 9 raw CSVs into SQL Server as bronze schema tables.
No transformations. Data lands exactly as it came from the source.

"""

import pandas as pd
import pyodbc
from sqlalchemy import create_engine, text
import os

# =============================================================
# CONFIGURATION
# =============================================================

SERVER   = r'DAPOLAPTOP\DAPOSQLSERVER'
DATABASE = 'enova_talent'
RAW_PATH = r'C:\Users\dobad\Desktop\Projects\enova-talent-intelligence\data\raw'

# Connection string using Windows integrated auth
CONN_STR = (
    f'mssql+pyodbc://{SERVER}/{DATABASE}'
    f'?driver=ODBC+Driver+17+for+SQL+Server'
    f'&trusted_connection=yes'
)

# =============================================================
# CONNECT
# =============================================================

print(f'Connecting to {SERVER}/{DATABASE}...')

try:
    engine = create_engine(CONN_STR, fast_executemany=True)
    with engine.connect() as conn:
        conn.execute(text('SELECT 1'))
    print('Connected.')
except Exception as e:
    print(f'Connection failed: {e}')
    raise

# =============================================================
# CREATE BRONZE SCHEMA
# =============================================================

with engine.connect() as conn:
    conn.execute(text("""
        IF NOT EXISTS (
            SELECT 1 FROM sys.schemas WHERE name = 'bronze'
        )
        EXEC('CREATE SCHEMA bronze')
    """))
    conn.commit()
    print('Bronze schema ready.')

# =============================================================
# LOAD TABLES
# =============================================================
# Each CSV is loaded as-is into a bronze table.
# All columns land as NVARCHAR so nothing gets silently
# converted or truncated during load. Silver layer handles
# type casting.
# =============================================================

tables = [
    'talentflow_jobs',
    'talentflow_candidates',
    'talentflow_applications',
    'talentflow_pipeline_events',
    'talentflow_offers',
    'peoplecore_employees',
    'peoplecore_performance',
    'peoplecore_compensation',
    'finance_headcount_plan',
]

for table in tables:
    csv_path = os.path.join(RAW_PATH, f'{table}.csv')

    if not os.path.exists(csv_path):
        print(f'  MISSING: {csv_path}')
        continue

    df = pd.read_csv(csv_path, dtype=str, keep_default_na=False)

    # Replace empty strings with None so they land as NULL in SQL
    df = df.replace({'': None, 'nan': None, 'None': None})

    target_table = f'bronze.{table}'

    df.to_sql(
        name=table,
        schema='bronze',
        con=engine,
        if_exists='replace',   # Drop and recreate on each run
        index=False,
    )

    print(f'  Loaded {target_table}: {len(df):,} rows x {len(df.columns)} cols')

print('\nBronze load complete.')
print(f'Database: {DATABASE}')
print(f'Schema:   bronze')
print(f'Tables:   {len(tables)}')