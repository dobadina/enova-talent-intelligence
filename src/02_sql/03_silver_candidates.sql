-- =============================================================
-- SILVER LAYER: candidates
-- Source: bronze.talentflow_candidates
--
-- Changes from bronze:
--   1. created_date cast to DATE
--   2. email normalised to lowercase
--   3. Probable duplicates flagged (same email, DQ-ATS-04)
-- =============================================================

IF OBJECT_ID('silver.candidates', 'U') IS NOT NULL
    DROP TABLE silver.candidates
GO

SELECT
    candidate_id,
    first_name,
    last_name,

    -- Normalise email to lowercase so joins work reliably
    LOWER(TRIM(email)) AS email,

    phone,
    location_city,
    location_country,
    current_company,
    current_title,
    linkedin_url,

    TRY_CONVERT(DATE, created_date, 23) AS created_date,

    -- Flag candidates who share an email with another record.
    -- These are probable duplicates (DQ-ATS-04).
    -- We flag rather than merge because merging requires
    -- manual confirmation that two records are the same person.
    CASE
        WHEN LOWER(TRIM(email)) IN (
            SELECT LOWER(TRIM(email))
            FROM bronze.talentflow_candidates
            GROUP BY LOWER(TRIM(email))
            HAVING COUNT(*) > 1
        )
        THEN 'PROBABLE_DUPLICATE'
        ELSE ''
    END AS dq_duplicate_flag

INTO silver.candidates
FROM bronze.talentflow_candidates
GO


-- =============================================================
-- VALIDATION
-- =============================================================

-- 1. Row count
SELECT 'bronze' AS layer, COUNT(*) AS row_count FROM bronze.talentflow_candidates
UNION ALL
SELECT 'silver',           COUNT(*)               FROM silver.candidates

-- 2. Duplicate flag distribution
SELECT
    dq_duplicate_flag,
    COUNT(*) AS row_count
FROM silver.candidates
GROUP BY dq_duplicate_flag

-- 3. How many unique emails exist vs total rows
SELECT
    COUNT(*)            AS total_rows,
    COUNT(DISTINCT email) AS unique_emails
FROM silver.candidates

-- 4. Any dates that failed to parse
SELECT
    COUNT(*) AS null_created_dates
FROM silver.candidates
WHERE created_date IS NULL