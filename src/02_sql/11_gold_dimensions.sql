-- =============================================================
-- dim_department
-- =============================================================

IF OBJECT_ID('gold.dim_department', 'U') IS NOT NULL
    DROP TABLE gold.dim_department
GO

SELECT
    ROW_NUMBER() OVER (ORDER BY canonical_name) AS department_key,
    canonical_name,
    hris_name,
    finance_name
INTO gold.dim_department
FROM (
    VALUES
        ('Technology',           'Engineering', 'Engineering & Product'),
        ('Product',              'Product',     'Engineering & Product'),
        ('Data and Analytics',   'Analytics',   'Analytics'),
        ('Commercial',           'Growth',      'Sales & Marketing'),
        ('Finance',              'Finance',     'Finance'),
        ('Operations',           'Operations',  'Operations'),
        ('People',               'HR',          'HR & Legal'),
        ('Legal and Compliance', 'Legal',       'HR & Legal')
) AS d(canonical_name, hris_name, finance_name)
GO

-- =============================================================
-- dim_source
-- =============================================================

IF OBJECT_ID('gold.dim_source', 'U') IS NOT NULL
    DROP TABLE gold.dim_source
GO

SELECT
    ROW_NUMBER() OVER (ORDER BY source_name) AS source_key,
    source_name,
    source_category
INTO gold.dim_source
FROM (
    VALUES
        ('LinkedIn Organic',       'Organic'),
        ('LinkedIn Paid',          'Paid'),
        ('LinkedIn Recruiter',     'Outbound'),
        ('Employee Referral',      'Referral'),
        ('Direct Application',     'Organic'),
        ('Indeed',                 'Organic'),
        ('Glassdoor',              'Organic'),
        ('Recruitment Agency',     'Outbound'),
        ('GitHub Sourcing',        'Outbound'),
        ('University Partnership', 'Outbound'),
        ('Other',                  'Other')
) AS s(source_name, source_category)
GO

-- =============================================================
-- dim_job (rebuild now that dim_department exists)
-- =============================================================

IF OBJECT_ID('gold.dim_job', 'U') IS NOT NULL
    DROP TABLE gold.dim_job
GO

SELECT
    j.job_id                AS job_key,
    j.job_title,
    j.department,
    d.department_key,
    j.location,
    j.job_level,
    j.employment_type,
    j.hiring_manager_id,
    j.recruiter_id,
    j.headcount_approved,
    j.status,
    j.requisition_open_date,
    j.requisition_close_date,
    j.target_fill_date,
    CASE
        WHEN j.requisition_close_date IS NOT NULL
        THEN DATEDIFF(DAY, j.requisition_open_date, j.requisition_close_date)
        ELSE NULL
    END AS days_open,
    j.dq_unclosed_flag
INTO gold.dim_job
FROM silver.jobs j
LEFT JOIN gold.dim_department d ON d.canonical_name = j.department
GO

-- =============================================================
-- dim_candidate (rebuild)
-- =============================================================

IF OBJECT_ID('gold.dim_candidate', 'U') IS NOT NULL
    DROP TABLE gold.dim_candidate
GO

SELECT
    candidate_id            AS candidate_key,
    first_name,
    last_name,
    CONCAT(first_name, ' ', last_name) AS full_name,
    location_city,
    location_country,
    current_company,
    current_title,
    created_date,
    dq_duplicate_flag
INTO gold.dim_candidate
FROM silver.candidates
GO

-- =============================================================
-- VALIDATION
-- =============================================================

SELECT 'gold.dim_date'       AS table_name, COUNT(*) AS rows FROM gold.dim_date
UNION ALL SELECT 'gold.dim_department', COUNT(*) FROM gold.dim_department
UNION ALL SELECT 'gold.dim_source',     COUNT(*) FROM gold.dim_source
UNION ALL SELECT 'gold.dim_job',        COUNT(*) FROM gold.dim_job
UNION ALL SELECT 'gold.dim_candidate',  COUNT(*) FROM gold.dim_candidate