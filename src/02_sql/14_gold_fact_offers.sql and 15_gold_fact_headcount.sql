IF OBJECT_ID('gold.fact_headcount', 'U') IS NOT NULL
    DROP TABLE gold.fact_headcount
GO

SELECT
    h.plan_id,
    h.department                                AS finance_department,
    h.department_canonical,
    h.quarter,

    h.headcount_approved,
    h.headcount_emergency_approved,
    h.headcount_total_approved,
    h.headcount_actual,
    h.dq_plan_flag,

    CASE
        WHEN h.headcount_total_approved IS NOT NULL
         AND h.headcount_actual         IS NOT NULL
        THEN h.headcount_actual - h.headcount_total_approved
        ELSE NULL
    END AS headcount_variance,

    CASE
        WHEN h.headcount_total_approved IS NOT NULL
         AND h.headcount_total_approved > 0
         AND h.headcount_actual         IS NOT NULL
        THEN CAST(h.headcount_actual - h.headcount_total_approved AS FLOAT)
             / h.headcount_total_approved * 100
        ELSE NULL
    END AS headcount_variance_pct,

    CAST(
        CASE h.quarter
            WHEN 'Q1_2023' THEN '2023-01-01'
            WHEN 'Q2_2023' THEN '2023-04-01'
            WHEN 'Q3_2023' THEN '2023-07-01'
            WHEN 'Q4_2023' THEN '2023-10-01'
            WHEN 'Q1_2024' THEN '2024-01-01'
            WHEN 'Q2_2024' THEN '2024-04-01'
            WHEN 'Q3_2024' THEN '2024-07-01'
            WHEN 'Q4_2024' THEN '2024-10-01'
            WHEN 'Q1_2025' THEN '2025-01-01'
            WHEN 'Q2_2025' THEN '2025-04-01'
        END
    AS DATE) AS quarter_start_date,

    dd.date_key AS quarter_date_key

INTO gold.fact_headcount
FROM silver.headcount_plan h
-- Join directly to dim_date, no dim_department join needed
-- since Finance dept names do not map 1-to-1 with canonical names
LEFT JOIN gold.dim_date dd ON dd.calendar_date = CAST(
    CASE h.quarter
        WHEN 'Q1_2023' THEN '2023-01-01'
        WHEN 'Q2_2023' THEN '2023-04-01'
        WHEN 'Q3_2023' THEN '2023-07-01'
        WHEN 'Q4_2023' THEN '2023-10-01'
        WHEN 'Q1_2024' THEN '2024-01-01'
        WHEN 'Q2_2024' THEN '2024-04-01'
        WHEN 'Q3_2024' THEN '2024-07-01'
        WHEN 'Q4_2024' THEN '2024-10-01'
        WHEN 'Q1_2025' THEN '2025-01-01'
        WHEN 'Q2_2025' THEN '2025-04-01'
    END
AS DATE)
GO

-- Validation
SELECT COUNT(*) AS total_rows FROM gold.fact_headcount

SELECT
    finance_department,
    quarter,
    headcount_total_approved,
    headcount_actual,
    headcount_variance,
    dq_plan_flag
FROM gold.fact_headcount
ORDER BY finance_department, quarter