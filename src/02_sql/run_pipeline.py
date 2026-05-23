import pyodbc
import pandas as pd
from datetime import datetime
import os

SERVER   = r'DAPOLAPTOP\DAPOSQLSERVER'
DATABASE = 'enova_talent'
RAW_PATH = r'C:\Users\dobad\Desktop\Projects\enova-talent-intelligence\data\raw'

CONN_STR = (
    f'DRIVER={{ODBC Driver 17 for SQL Server}};'
    f'SERVER={SERVER};'
    f'DATABASE={DATABASE};'
    f'Trusted_Connection=yes;'
)

def log(msg):
    print(f'[{datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] {msg}')

def run_pipeline():
    log('Pipeline started')

    conn = pyodbc.connect(CONN_STR)
    conn.autocommit = True
    cursor = conn.cursor()
    log('Connected to SQL Server')

    # Bronze load
    log('Loading bronze...')
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

    total_bronze = 0
    for table in tables:
        csv_path = os.path.join(RAW_PATH, f'{table}.csv')
        df = pd.read_csv(csv_path, dtype=str, keep_default_na=False)
        df = df.replace({'': None, 'nan': None, 'None': None})

        cursor.execute(f'TRUNCATE TABLE bronze.{table}')

        cols = ', '.join(df.columns)
        placeholders = ', '.join(['?' for _ in df.columns])
        insert_sql = f'INSERT INTO bronze.{table} ({cols}) VALUES ({placeholders})'

        rows = [tuple(r) for r in df.itertuples(index=False, name=None)]
        cursor.executemany(insert_sql, rows)

        log(f'  bronze.{table}: {len(df):,} rows')
        total_bronze += len(df)

    log(f'Bronze complete: {total_bronze:,} total rows')

    # Silver and gold via stored procedure
    log('Running silver and gold via pipeline.run...')
    try:
        cursor.execute("EXEC pipeline.run @triggered_by = 'scheduled'")

        # Skip through result sets until we get the log entry
        # pipeline.run returns multiple result sets from the sub-procedures
        # The last one is our log entry
        result = None
        while True:
            try:
                rows = cursor.fetchall()
                if rows:
                    result = rows
                if not cursor.nextset():
                    break
            except:
                break

        if result:
            row = result[0]
            log(f'Pipeline complete')
            log(f'  Status:          {row[4]}')
            log(f'  Duration:        {row[3]} seconds')
            log(f'  Silver rows:     {row[5]:,}')
            log(f'  Gold rows:       {row[6]:,}')
            if row[7]:
                log(f'  Error:           {row[7]}')
        else:
            log('Pipeline complete - no log entry returned')

    except Exception as e:
        log(f'Pipeline error: {e}')

    cursor.close()
    conn.close()

if __name__ == '__main__':
    run_pipeline()