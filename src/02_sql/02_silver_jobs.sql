-- =============================================================
-- SILVER LAYER: jobs
-- Source: bronze.talentflow_jobs
--
-- Changes from bronze:
--   1. Date columns cast from NVARCHAR to DATE
--   2. Status standardised to lowercase
--   3. headcount_approved cast to INT
--   4. Requisitions open > 120 days with no close date
--      flagged as possibly unclosed (DQ-ATS-07)
-- =============================================================

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'silver')
    EXEC('CREATE SCHEMA silver')
GO

-- Drop and recreate
IF OBJECT_ID('silver.jobs', 'U') IS NOT NULL
    DROP TABLE silver.jobs
GO

SELECT
    job_id,
    job_title,
    department,
    location,
    employment_type,

    -- Cast dates. TRY_CONVERT returns NULL if the value cannot
    -- be parsed as a date rather than throwing an error.
    -- All dates in bronze are YYYY-MM-DD so style 23 is correct.
    TRY_CONVERT(DATE, requisition_open_date,  23) AS requisition_open_date,
    TRY_CONVERT(DATE, requisition_close_date, 23) AS requisition_close_date,
    TRY_CONVERT(DATE, target_fill_date,       23) AS target_fill_date,

    hiring_manager_id,
    recruiter_id,

    TRY_CAST(headcount_approved AS INT) AS headcount_approved,

    -- Standardise status to lowercase and trim whitespace
    LOWER(TRIM(status)) AS status,

    job_level,

    -- Flag requisitions that are still open but were opened
    -- more than 120 days ago. These are candidates for DQ-ATS-07
    -- (filled jobs left open in the ATS). The cross-table fix
    -- happens in gold once we can join to employees.
    CASE
        WHEN LOWER(TRIM(status)) = 'open'
         AND TRY_CONVERT(DATE, requisition_open_date, 23) < DATEADD(DAY, -120, GETDATE())
        THEN 'POSSIBLY_UNCLOSED'
        ELSE ''
    END AS dq_unclosed_flag

INTO silver.jobs
FROM bronze.talentflow_jobs
GO


-- =============================================================
-- VALIDATION
-- =============================================================

-- 1. Row count: silver must equal bronze
SELECT
    'bronze' AS layer,
    COUNT(*) AS row_count
FROM bronze.talentflow_jobs
UNION ALL
SELECT
    'silver',
    COUNT(*)
FROM silver.jobs

-- 2. Date cast success rate
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN requisition_open_date  IS NOT NULL THEN 1 ELSE 0 END) AS open_date_parsed,
    SUM(CASE WHEN requisition_close_date IS NOT NULL THEN 1 ELSE 0 END) AS close_date_parsed,
    SUM(CASE WHEN target_fill_date       IS NOT NULL THEN 1 ELSE 0 END) AS target_date_parsed
FROM silver.jobs

-- 3. Status values: should only be open, filled, cancelled, on_hold
SELECT
    status,
    COUNT(*) AS row_count
FROM silver.jobs
GROUP BY status
ORDER BY row_count DESC

-- 4. Unclosed flag check
SELECT
    dq_unclosed_flag,
    COUNT(*) AS row_count
FROM silver.jobs
GROUP BY dq_unclosed_flag