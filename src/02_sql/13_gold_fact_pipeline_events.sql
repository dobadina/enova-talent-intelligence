-- =============================================================
-- GOLD LAYER: fact_pipeline_events
-- One row per stage transition.
-- =============================================================

IF OBJECT_ID('gold.fact_pipeline_events', 'U') IS NOT NULL
    DROP TABLE gold.fact_pipeline_events
GO

WITH events_with_next AS (
    SELECT
        e.event_id,
        e.application_id,
        e.from_stage,
        e.to_stage,
        e.event_date,
        e.event_type,
        e.rejection_reason,
        e.dq_date_sequence_flag,
        e.dq_stage_skip_flag,
        a.job_id,
        a.source,
        a.hired,
        -- Next event date for this application to compute days in stage
        LEAD(e.event_date) OVER (
            PARTITION BY e.application_id
            ORDER BY e.event_date, e.event_id
        ) AS next_event_date
    FROM silver.pipeline_events e
    LEFT JOIN silver.applications a ON a.application_id = e.application_id
)
SELECT
    e.event_id,
    e.application_id,
    e.from_stage,
    e.to_stage,
    e.event_date,
    e.event_type,
    e.rejection_reason,
    e.dq_date_sequence_flag,
    e.dq_stage_skip_flag,

    j.job_key,
    j.department,
    j.job_level,
    j.recruiter_id,
    d.department_key,
    dd.date_key                                     AS event_date_key,

    -- Days spent in this stage.
    -- NULL for the final event (no next event to measure to).
    -- Also NULL for flagged sequence errors and stage skips
    -- to avoid polluting velocity calculations.
    CASE
        WHEN e.dq_date_sequence_flag = 'DATE_SEQUENCE_ERROR' THEN NULL
        WHEN e.dq_stage_skip_flag    = 'STAGE_SKIP_DETECTED' THEN NULL
        WHEN e.next_event_date IS NOT NULL
        THEN DATEDIFF(DAY, e.event_date, e.next_event_date)
        ELSE NULL
    END AS days_in_stage,

    -- Flag whether this event is on the critical path to hire
    -- (i.e. the application eventually resulted in a hire)
    e.hired                                         AS application_hired

INTO gold.fact_pipeline_events
FROM events_with_next e
LEFT JOIN gold.dim_job        j   ON j.job_key        = e.job_id
LEFT JOIN gold.dim_department d   ON d.canonical_name = j.department
LEFT JOIN gold.dim_date       dd  ON dd.calendar_date = e.event_date
GO

-- =============================================================
-- VALIDATION
-- =============================================================

SELECT COUNT(*) AS total_rows FROM gold.fact_pipeline_events

-- Average days in stage by stage name
-- This is where the Technical Assessment bottleneck should appear
SELECT
    to_stage                                        AS stage,
    COUNT(*)                                        AS total_events,
    AVG(CAST(days_in_stage AS FLOAT))               AS avg_days_in_stage,
    MAX(days_in_stage)                              AS max_days_in_stage
FROM gold.fact_pipeline_events
WHERE days_in_stage IS NOT NULL
  AND days_in_stage >= 0
GROUP BY to_stage
ORDER BY avg_days_in_stage DESC

-- Technical Assessment by department: should show Technology
-- averaging ~11 days vs ~4 days for others
SELECT
    department,
    AVG(CAST(days_in_stage AS FLOAT))               AS avg_days_in_tech_assess
FROM gold.fact_pipeline_events
WHERE to_stage    = 'Technical Assessment'
  AND days_in_stage IS NOT NULL
  AND days_in_stage >= 0
GROUP BY department
ORDER BY avg_days_in_tech_assess DESC