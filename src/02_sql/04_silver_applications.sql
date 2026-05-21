-- =============================================================
-- SILVER LAYER: applications
-- Source: bronze.talentflow_applications
--
-- Changes from bronze:
--   1. Date columns cast to DATE
--      Handles YYYY-MM-DD, DD/MM/YYYY and MM/DD/YYYY
--   2. Source field standardised to canonical values (DQ-ATS-05)
--   3. hired/rejected/withdrawn cast to BIT
-- =============================================================

IF OBJECT_ID('silver.applications', 'U') IS NOT NULL
    DROP TABLE silver.applications
GO

-- Source name mapping applied inline using CASE.
-- Every messy variant maps to one of the 11 canonical values
-- defined in step1_foundations.md.
SELECT
    application_id,
    candidate_id,
    job_id,

    CASE
        WHEN LOWER(TRIM(source)) IN ('linkedin organic', 'linkedin', 'linked in',
             'li', 'linkedin jobs', 'linkedin.com')
            THEN 'LinkedIn Organic'
        WHEN LOWER(TRIM(source)) IN ('linkedin paid', 'linkedin sponsored',
             'linkedin ads', 'linkedin paid job')
            THEN 'LinkedIn Paid'
        WHEN LOWER(TRIM(source)) IN ('linkedin recruiter', 'li recruiter',
             'linkedin inmail', 'linkedin inmails')
            THEN 'LinkedIn Recruiter'
        WHEN LOWER(TRIM(source)) IN ('employee referral', 'referral',
             'internal referral', 'ee referral', 'employee ref')
            THEN 'Employee Referral'
        WHEN LOWER(TRIM(source)) IN ('direct application', 'direct',
             'careers page', 'company website', 'careers site')
            THEN 'Direct Application'
        WHEN LOWER(TRIM(source)) IN ('indeed', 'indeed.com')
            THEN 'Indeed'
        WHEN LOWER(TRIM(source)) IN ('glassdoor', 'glassdoor.com')
            THEN 'Glassdoor'
        WHEN LOWER(TRIM(source)) IN ('recruitment agency', 'agency',
             'external recruiter', 'headhunter')
            THEN 'Recruitment Agency'
        WHEN LOWER(TRIM(source)) IN ('github sourcing', 'github')
            THEN 'GitHub Sourcing'
        WHEN LOWER(TRIM(source)) IN ('university partnership')
            THEN 'University Partnership'
        ELSE 'Other'
    END AS source,

    source_subtype,

    -- Date parsing handles three formats.
    -- TRY_CONVERT with style 23 handles YYYY-MM-DD.
    -- For slash formats we use PARSE with culture hints.
    -- If both fail the date lands as NULL and gets flagged.
    COALESCE(
        TRY_CONVERT(DATE, application_date, 23),
        TRY_CONVERT(DATE, application_date, 103),
        TRY_CONVERT(DATE, application_date, 101)
    ) AS application_date,

    COALESCE(
        TRY_CONVERT(DATE, current_stage_date, 23),
        TRY_CONVERT(DATE, current_stage_date, 103),
        TRY_CONVERT(DATE, current_stage_date, 101)
    ) AS current_stage_date,

    current_stage,

    CAST(CASE WHEN LOWER(TRIM(hired))    = 'true' THEN 1 ELSE 0 END AS BIT) AS hired,
    CAST(CASE WHEN LOWER(TRIM(rejected)) = 'true' THEN 1 ELSE 0 END AS BIT) AS rejected,
    CAST(CASE WHEN LOWER(TRIM(withdrawn))= 'true' THEN 1 ELSE 0 END AS BIT) AS withdrawn

INTO silver.applications
FROM bronze.talentflow_applications
GO


-- =============================================================
-- VALIDATION
-- =============================================================

-- 1. Row count
SELECT 'bronze' AS layer, COUNT(*) AS row_count FROM bronze.talentflow_applications
UNION ALL
SELECT 'silver',           COUNT(*)               FROM silver.applications

-- 2. Source values: should only be canonical names after cleaning
SELECT
    source,
    COUNT(*) AS row_count
FROM silver.applications
GROUP BY source
ORDER BY row_count DESC

-- 3. Compare source before and after: how many were non-canonical in bronze
SELECT
    SUM(CASE WHEN source IN (
        'LinkedIn Organic','LinkedIn Paid','LinkedIn Recruiter',
        'Employee Referral','Direct Application','Indeed','Glassdoor',
        'Recruitment Agency','GitHub Sourcing','University Partnership','Other'
    ) THEN 1 ELSE 0 END) AS canonical_in_bronze,
    COUNT(*) AS total
FROM bronze.talentflow_applications

-- 4. Date parse failures
SELECT
    SUM(CASE WHEN application_date   IS NULL THEN 1 ELSE 0 END) AS null_application_dates,
    SUM(CASE WHEN current_stage_date IS NULL THEN 1 ELSE 0 END) AS null_stage_dates
FROM silver.applications

-- 5. Hired/rejected/withdrawn counts
SELECT
    SUM(CAST(hired     AS INT)) AS total_hired,
    SUM(CAST(rejected  AS INT)) AS total_rejected,
    SUM(CAST(withdrawn AS INT)) AS total_withdrawn
FROM silver.applications