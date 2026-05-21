-- =============================================================
-- SILVER LAYER: pipeline_events
-- Source: bronze.talentflow_pipeline_events
--
-- Changes from bronze:
--   1. Stage names standardised to canonical values (DQ-ATS-01)
--   2. event_date cast to DATE handling mixed formats (DQ-ATS-02)
--   3. NULL rejection reasons set to REASON_NOT_RECORDED (DQ-ATS-08)
--   4. Impossible date sequences flagged (DQ-ATS-06)
--   5. Stage skips flagged (DQ-ATS-09)
-- =============================================================

IF OBJECT_ID('silver.pipeline_events', 'U') IS NOT NULL
    DROP TABLE silver.pipeline_events
GO

-- Step 1: standardise stage names and parse dates
SELECT
    event_id,
    application_id,

    CASE
        WHEN LOWER(TRIM(from_stage)) IN ('phone screen','phone_screen',
             'phone interview','recruiter call','recruiter_screen',
             'recruiter screen')
            THEN 'Recruiter Screen'
        WHEN LOWER(TRIM(from_stage)) IN ('hm screen','hm call',
             'hiring_manager_screen','manager screen',
             'hiring manager screen')
            THEN 'Hiring Manager Screen'
        WHEN LOWER(TRIM(from_stage)) IN ('tech assessment','technical_assessment',
             'take home task','coding challenge','technical assessment')
            THEN 'Technical Assessment'
        WHEN LOWER(TRIM(from_stage)) IN ('tech interview','technical_interview',
             'live coding','technical interview')
            THEN 'Technical Interview'
        WHEN LOWER(TRIM(from_stage)) IN ('panel','final panel','final interview',
             'final_panel_interview','final panel interview')
            THEN 'Final Panel Interview'
        WHEN LOWER(TRIM(from_stage)) IN ('refs','reference_check',
             'references','reference check')
            THEN 'Reference Check'
        WHEN LOWER(TRIM(from_stage)) IN ('cv review','resume review',
             'cv screen','resume_screen','resume screen')
            THEN 'Resume Screen'
        ELSE TRIM(from_stage)
    END AS from_stage,

    CASE
        WHEN LOWER(TRIM(to_stage)) IN ('phone screen','phone_screen',
             'phone interview','recruiter call','recruiter_screen',
             'recruiter screen')
            THEN 'Recruiter Screen'
        WHEN LOWER(TRIM(to_stage)) IN ('hm screen','hm call',
             'hiring_manager_screen','manager screen',
             'hiring manager screen')
            THEN 'Hiring Manager Screen'
        WHEN LOWER(TRIM(to_stage)) IN ('tech assessment','technical_assessment',
             'take home task','coding challenge','technical assessment')
            THEN 'Technical Assessment'
        WHEN LOWER(TRIM(to_stage)) IN ('tech interview','technical_interview',
             'live coding','technical interview')
            THEN 'Technical Interview'
        WHEN LOWER(TRIM(to_stage)) IN ('panel','final panel','final interview',
             'final_panel_interview','final panel interview')
            THEN 'Final Panel Interview'
        WHEN LOWER(TRIM(to_stage)) IN ('refs','reference_check',
             'references','reference check')
            THEN 'Reference Check'
        WHEN LOWER(TRIM(to_stage)) IN ('cv review','resume review',
             'cv screen','resume_screen','resume screen')
            THEN 'Resume Screen'
        ELSE TRIM(to_stage)
    END AS to_stage,

    COALESCE(
        TRY_CONVERT(DATE, event_date, 23),
        TRY_CONVERT(DATE, event_date, 103),
        TRY_CONVERT(DATE, event_date, 101)
    ) AS event_date,

    event_type,

    CASE
        WHEN (rejection_reason IS NULL
           OR TRIM(rejection_reason) IN ('', 'nan', 'None'))
         AND LOWER(TRIM(event_type)) = 'rejected'
        THEN 'REASON_NOT_RECORDED'
        ELSE rejection_reason
    END AS rejection_reason,

    interviewer_id,
    notes

INTO #pipeline_staged
FROM bronze.talentflow_pipeline_events
GO

-- Step 2: add impossible sequence and stage skip flags
-- Stage order lookup used for skip detection
;WITH stage_order AS (
    SELECT 'Applied'                AS stage_name, 0 AS stage_num
    UNION ALL SELECT 'Resume Screen',              1
    UNION ALL SELECT 'Recruiter Screen',           2
    UNION ALL SELECT 'Hiring Manager Screen',      3
    UNION ALL SELECT 'Technical Assessment',       4
    UNION ALL SELECT 'Technical Interview',        5
    UNION ALL SELECT 'Final Panel Interview',      6
    UNION ALL SELECT 'Reference Check',            7
    UNION ALL SELECT 'Offer',                      8
    UNION ALL SELECT 'Offer Accepted',             9
    UNION ALL SELECT 'Hired',                     10
),
events_with_order AS (
    SELECT
        p.*,
        so_from.stage_num AS from_order,
        so_to.stage_num   AS to_order,
        -- Previous event date for this application
        LAG(p.event_date) OVER (
            PARTITION BY p.application_id
            ORDER BY p.event_date, p.event_id
        ) AS prev_event_date
    FROM #pipeline_staged p
    LEFT JOIN stage_order so_from ON so_from.stage_name = p.from_stage
    LEFT JOIN stage_order so_to   ON so_to.stage_name   = p.to_stage
)
SELECT
    event_id,
    application_id,
    from_stage,
    to_stage,
    event_date,
    event_type,
    rejection_reason,
    interviewer_id,
    notes,

    -- Flag events where this date is before the previous event
    -- for the same application (DQ-ATS-06)
    CASE
        WHEN prev_event_date IS NOT NULL
         AND event_date < prev_event_date
        THEN 'DATE_SEQUENCE_ERROR'
        ELSE ''
    END AS dq_date_sequence_flag,

    -- Flag events where the stage jumps more than 2 levels (DQ-ATS-09)
    CASE
        WHEN from_order IS NOT NULL
         AND to_order   IS NOT NULL
         AND (to_order - from_order) > 2
        THEN 'STAGE_SKIP_DETECTED'
        ELSE ''
    END AS dq_stage_skip_flag

INTO silver.pipeline_events
FROM events_with_order

DROP TABLE #pipeline_staged
GO


-- =============================================================
-- VALIDATION
-- =============================================================

-- 1. Row count
SELECT 'bronze' AS layer, COUNT(*) AS row_count
FROM bronze.talentflow_pipeline_events
UNION ALL
SELECT 'silver', COUNT(*)
FROM silver.pipeline_events

-- 2. Stage name counts: should be 11 unique from_stage,
--    11 unique to_stage after cleaning
SELECT
    COUNT(DISTINCT from_stage) AS unique_from_stages,
    COUNT(DISTINCT to_stage)   AS unique_to_stages
FROM silver.pipeline_events

-- 3. Date parse failures
SELECT
    SUM(CASE WHEN event_date IS NULL THEN 1 ELSE 0 END) AS null_dates
FROM silver.pipeline_events

-- 4. DQ flags
SELECT
    dq_date_sequence_flag,
    COUNT(*) AS row_count
FROM silver.pipeline_events
GROUP BY dq_date_sequence_flag

SELECT
    dq_stage_skip_flag,
    COUNT(*) AS row_count
FROM silver.pipeline_events
GROUP BY dq_stage_skip_flag

-- 5. Missing rejection reasons
SELECT
    rejection_reason,
    COUNT(*) AS row_count
FROM silver.pipeline_events
WHERE event_type = 'rejected'
GROUP BY rejection_reason
ORDER BY row_count DESC