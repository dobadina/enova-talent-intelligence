CREATE OR ALTER PROCEDURE gold.load_all
AS
BEGIN
    SET NOCOUNT ON

    -- dim_date (only rebuild if empty)
    IF NOT EXISTS (SELECT 1 FROM gold.dim_date)
    BEGIN
        ;WITH date_series AS (
            SELECT CAST('2023-01-01' AS DATE) AS calendar_date
            UNION ALL
            SELECT DATEADD(DAY, 1, calendar_date)
            FROM date_series
            WHERE calendar_date < '2026-12-31'
        )
        INSERT INTO gold.dim_date
        SELECT
            CAST(FORMAT(calendar_date, 'yyyyMMdd') AS INT),
            calendar_date,
            YEAR(calendar_date),
            MONTH(calendar_date),
            FORMAT(calendar_date, 'MMMM'),
            FORMAT(calendar_date, 'MMM'),
            DATEPART(QUARTER, calendar_date),
            CONCAT('Q', DATEPART(QUARTER, calendar_date), '_', YEAR(calendar_date)),
            DATEPART(WEEK, calendar_date),
            DATEPART(WEEKDAY, calendar_date),
            FORMAT(calendar_date, 'dddd'),
            CAST(CASE WHEN DATEPART(WEEKDAY, calendar_date) IN (1,7)
                      THEN 1 ELSE 0 END AS BIT)
        FROM date_series
        OPTION (MAXRECURSION 2000)
    END

    -- dim_department
    TRUNCATE TABLE gold.dim_department

    INSERT INTO gold.dim_department
    SELECT
        ROW_NUMBER() OVER (ORDER BY canonical_name),
        canonical_name, hris_name, finance_name
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

    -- dim_source
    TRUNCATE TABLE gold.dim_source

    INSERT INTO gold.dim_source
    SELECT
        ROW_NUMBER() OVER (ORDER BY source_name),
        source_name, source_category
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

    -- dim_job
    TRUNCATE TABLE gold.dim_job

    INSERT INTO gold.dim_job
    SELECT
        j.job_id, j.job_title, j.department, d.department_key,
        j.location, j.job_level, j.employment_type,
        j.hiring_manager_id, j.recruiter_id, j.headcount_approved,
        j.status, j.requisition_open_date, j.requisition_close_date,
        j.target_fill_date,
        CASE
            WHEN j.requisition_close_date IS NOT NULL
            THEN DATEDIFF(DAY, j.requisition_open_date, j.requisition_close_date)
            ELSE NULL
        END,
        j.dq_unclosed_flag
    FROM silver.jobs j
    LEFT JOIN gold.dim_department d ON d.canonical_name = j.department

    -- dim_candidate
    TRUNCATE TABLE gold.dim_candidate

    INSERT INTO gold.dim_candidate
    SELECT
        candidate_id, first_name, last_name,
        CONCAT(first_name, ' ', last_name),
        location_city, location_country,
        current_company, current_title,
        created_date, dq_duplicate_flag
    FROM silver.candidates

    -- fact_applications
    TRUNCATE TABLE gold.fact_applications

    INSERT INTO gold.fact_applications
    SELECT
        a.application_id,
        a.candidate_id, a.job_id,
        s.source_key, d.department_key,
        dd_app.date_key, dd_hire.date_key,
        a.application_date, a.current_stage,
        a.hired, a.rejected, a.withdrawn,
        e.start_date,
        CASE
            WHEN a.hired = 1 AND e.start_date IS NOT NULL
            THEN DATEDIFF(DAY, a.application_date, e.start_date)
            ELSE NULL
        END,
        CASE
            WHEN o.offer_date IS NOT NULL
            THEN DATEDIFF(DAY, a.application_date, o.offer_date)
            ELSE NULL
        END,
        o.offer_amount, o.offer_currency, o.offer_status, o.equity_offered,
        a.source, src.source_category,
        j.job_title, j.job_level, j.department,
        j.recruiter_id, j.hiring_manager_id,
        perf.avg_rating,
        ISNULL(e.pre_ats, 0)
    FROM silver.applications a
    LEFT JOIN gold.dim_source     src  ON src.source_name  = a.source
    LEFT JOIN gold.dim_job        j    ON j.job_key        = a.job_id
    LEFT JOIN gold.dim_department d    ON d.canonical_name = j.department
    LEFT JOIN gold.dim_source     s    ON s.source_name    = a.source
    LEFT JOIN (
        SELECT ats_candidate_id, start_date, employee_id, pre_ats
        FROM silver.employees
        WHERE ats_candidate_id IS NOT NULL
    ) e ON e.ats_candidate_id = a.candidate_id AND a.hired = 1
    LEFT JOIN gold.dim_date dd_app  ON dd_app.calendar_date  = a.application_date
    LEFT JOIN gold.dim_date dd_hire ON dd_hire.calendar_date = e.start_date
    LEFT JOIN (
        SELECT *
        FROM (
            SELECT *,
                ROW_NUMBER() OVER (
                    PARTITION BY application_id
                    ORDER BY CASE offer_status
                        WHEN 'accepted'  THEN 1
                        WHEN 'declined'  THEN 2
                        WHEN 'rescinded' THEN 3
                        ELSE 4
                    END
                ) AS rn
            FROM silver.offers
        ) ranked
        WHERE rn = 1
    ) o ON o.application_id = a.application_id
    LEFT JOIN (
        SELECT employee_id, AVG(CAST(rating AS FLOAT)) AS avg_rating
        FROM silver.performance
        GROUP BY employee_id
    ) perf ON perf.employee_id = e.employee_id

    -- fact_pipeline_events
    TRUNCATE TABLE gold.fact_pipeline_events

    INSERT INTO gold.fact_pipeline_events
    SELECT
        e.event_id, e.application_id,
        e.from_stage, e.to_stage, e.event_date, e.event_type,
        e.rejection_reason, e.dq_date_sequence_flag, e.dq_stage_skip_flag,
        j.job_key, j.department, j.job_level, j.recruiter_id,
        d.department_key, dd.date_key,
        CASE
            WHEN e.dq_date_sequence_flag = 'DATE_SEQUENCE_ERROR' THEN NULL
            WHEN e.dq_stage_skip_flag    = 'STAGE_SKIP_DETECTED' THEN NULL
            WHEN LEAD(e.event_date) OVER (
                PARTITION BY e.application_id
                ORDER BY e.event_date, e.event_id) IS NOT NULL
            THEN DATEDIFF(DAY, e.event_date,
                LEAD(e.event_date) OVER (
                    PARTITION BY e.application_id
                    ORDER BY e.event_date, e.event_id))
            ELSE NULL
        END,
        a.hired
    FROM silver.pipeline_events e
    LEFT JOIN silver.applications  a  ON a.application_id = e.application_id
    LEFT JOIN gold.dim_job         j  ON j.job_key        = a.job_id
    LEFT JOIN gold.dim_department  d  ON d.canonical_name = j.department
    LEFT JOIN gold.dim_date        dd ON dd.calendar_date = e.event_date

    -- fact_offers
    TRUNCATE TABLE gold.fact_offers

    INSERT INTO gold.fact_offers
    SELECT
        o.offer_id, o.application_id,
        a.candidate_id, a.job_id,
        j.department, j.job_level, j.recruiter_id, d.department_key,
        dd_offer.date_key, dd_accept.date_key,
        o.offer_date, o.accepted_date,
        o.offer_amount, o.offer_currency, o.offer_status,
        o.equity_offered, o.decline_reason,
        CASE
            WHEN o.accepted_date IS NOT NULL
            THEN DATEDIFF(DAY, o.offer_date, o.accepted_date)
            ELSE NULL
        END,
        CAST(CASE WHEN o.offer_status = 'accepted' THEN 1 ELSE 0 END AS BIT)
    FROM silver.offers o
    LEFT JOIN silver.applications  a         ON a.application_id        = o.application_id
    LEFT JOIN gold.dim_job         j         ON j.job_key               = a.job_id
    LEFT JOIN gold.dim_department  d         ON d.canonical_name        = j.department
    LEFT JOIN gold.dim_date        dd_offer  ON dd_offer.calendar_date  = o.offer_date
    LEFT JOIN gold.dim_date        dd_accept ON dd_accept.calendar_date = o.accepted_date

    -- fact_headcount
    TRUNCATE TABLE gold.fact_headcount

    INSERT INTO gold.fact_headcount
    SELECT
        h.plan_id, h.department, h.department_canonical, h.quarter,
        h.headcount_approved, h.headcount_emergency_approved,
        h.headcount_total_approved, h.headcount_actual, h.dq_plan_flag,
        CASE
            WHEN h.headcount_total_approved IS NOT NULL
             AND h.headcount_actual         IS NOT NULL
            THEN h.headcount_actual - h.headcount_total_approved
            ELSE NULL
        END,
        CASE
            WHEN h.headcount_total_approved IS NOT NULL
             AND h.headcount_total_approved > 0
             AND h.headcount_actual         IS NOT NULL
            THEN CAST(h.headcount_actual - h.headcount_total_approved AS FLOAT)
                 / h.headcount_total_approved * 100
            ELSE NULL
        END,
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
        AS DATE),
        dd.date_key
    FROM silver.headcount_plan h
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

    -- Return row counts for logging
    SELECT
        (SELECT COUNT(*) FROM gold.dim_date)             AS dim_date,
        (SELECT COUNT(*) FROM gold.dim_department)       AS dim_department,
        (SELECT COUNT(*) FROM gold.dim_source)           AS dim_source,
        (SELECT COUNT(*) FROM gold.dim_job)              AS dim_job,
        (SELECT COUNT(*) FROM gold.dim_candidate)        AS dim_candidate,
        (SELECT COUNT(*) FROM gold.fact_applications)    AS fact_applications,
        (SELECT COUNT(*) FROM gold.fact_pipeline_events) AS fact_pipeline_events,
        (SELECT COUNT(*) FROM gold.fact_offers)          AS fact_offers,
        (SELECT COUNT(*) FROM gold.fact_headcount)       AS fact_headcount

END
GO

EXEC gold.load_all