IF OBJECT_ID('silver.headcount_plan', 'U') IS NOT NULL
    DROP TABLE silver.headcount_plan
GO

SELECT
    plan_id,
    department,

    CASE TRIM(department)
        WHEN 'Engineering & Product' THEN 'Technology / Product'
        WHEN 'Analytics'             THEN 'Data and Analytics'
        WHEN 'Sales & Marketing'     THEN 'Commercial'
        WHEN 'Finance'               THEN 'Finance'
        WHEN 'Operations'            THEN 'Operations'
        WHEN 'HR & Legal'            THEN 'People / Legal and Compliance'
        ELSE TRIM(department)
    END AS department_canonical,

    quarter,

    -- Cast via DECIMAL first to handle values stored as '50.0'
    TRY_CAST(TRY_CAST(headcount_approved AS DECIMAL(10,1)) AS INT) AS headcount_approved,
    TRY_CAST(TRY_CAST(headcount_actual   AS DECIMAL(10,1)) AS INT) AS headcount_actual,

    CASE
        WHEN TRIM(department) = 'Engineering & Product'
         AND TRIM(quarter)    = 'Q2_2024'
        THEN 7
        ELSE 0
    END AS headcount_emergency_approved,

    CASE
        WHEN TRIM(department) = 'Engineering & Product'
         AND TRIM(quarter)    = 'Q2_2024'
        THEN TRY_CAST(TRY_CAST(headcount_approved AS DECIMAL(10,1)) AS INT) + 7
        ELSE TRY_CAST(TRY_CAST(headcount_approved AS DECIMAL(10,1)) AS INT)
    END AS headcount_total_approved,

    notes,

    CASE
        WHEN headcount_approved IS NULL
        THEN 'PLAN_NOT_SUBMITTED'
        ELSE ''
    END AS dq_plan_flag

INTO silver.headcount_plan
FROM bronze.finance_headcount_plan
GO

-- Validation
SELECT 'bronze' AS layer, COUNT(*) AS row_count FROM bronze.finance_headcount_plan
UNION ALL
SELECT 'silver',           COUNT(*)               FROM silver.headcount_plan

SELECT
    department,
    quarter,
    headcount_approved,
    headcount_emergency_approved,
    headcount_total_approved,
    headcount_actual
FROM silver.headcount_plan
WHERE department = 'Engineering & Product'
ORDER BY quarter

SELECT
    department,
    quarter,
    headcount_approved,
    dq_plan_flag
FROM silver.headcount_plan
WHERE dq_plan_flag = 'PLAN_NOT_SUBMITTED'