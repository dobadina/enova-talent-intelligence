IF OBJECT_ID('gold.fact_applications', 'U') IS NOT NULL
    DROP TABLE gold.fact_applications
GO

-- Pre-filter offers to one row per application before the main join
;WITH ranked_offers AS (
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
    ) o
    WHERE rn = 1
)
SELECT
    a.application_id,
    a.candidate_id                              AS candidate_key,
    a.job_id                                    AS job_key,
    s.source_key,
    d.department_key,
    dd_app.date_key                             AS application_date_key,
    dd_hire.date_key                            AS hired_date_key,
    a.application_date,
    a.current_stage,
    a.hired,
    a.rejected,
    a.withdrawn,
    e.start_date                                AS hired_date,

    CASE
        WHEN a.hired = 1 AND e.start_date IS NOT NULL
        THEN DATEDIFF(DAY, a.application_date, e.start_date)
        ELSE NULL
    END AS days_to_hire,

    CASE
        WHEN o.offer_date IS NOT NULL
        THEN DATEDIFF(DAY, a.application_date, o.offer_date)
        ELSE NULL
    END AS days_to_offer,

    o.offer_amount,
    o.offer_currency,
    o.offer_status,
    o.equity_offered,
    a.source                                    AS source_name,
    src.source_category,
    j.job_title,
    j.job_level,
    j.department,
    j.recruiter_id,
    j.hiring_manager_id,
    perf.avg_rating                             AS avg_performance_rating,
    ISNULL(e.pre_ats, 0)                        AS pre_ats

INTO gold.fact_applications
FROM silver.applications a

LEFT JOIN gold.dim_source     src  ON src.source_name   = a.source
LEFT JOIN gold.dim_job        j    ON j.job_key         = a.job_id
LEFT JOIN gold.dim_department d    ON d.canonical_name  = j.department
LEFT JOIN gold.dim_source     s    ON s.source_name     = a.source

LEFT JOIN (
    SELECT ats_candidate_id, start_date, employee_id, pre_ats
    FROM silver.employees
    WHERE ats_candidate_id IS NOT NULL
) e ON e.ats_candidate_id = a.candidate_id
   AND a.hired = 1

LEFT JOIN gold.dim_date dd_app  ON dd_app.calendar_date = a.application_date
LEFT JOIN gold.dim_date dd_hire ON dd_hire.calendar_date = e.start_date
LEFT JOIN ranked_offers o       ON o.application_id     = a.application_id

LEFT JOIN (
    SELECT employee_id, AVG(CAST(rating AS FLOAT)) AS avg_rating
    FROM silver.performance
    GROUP BY employee_id
) perf ON perf.employee_id = e.employee_id
GO

-- =============================================================
-- VALIDATION
-- =============================================================

SELECT COUNT(*) AS total_rows FROM gold.fact_applications

SELECT
    application_id,
    COUNT(*) AS row_count
FROM gold.fact_applications
GROUP BY application_id
HAVING COUNT(*) > 1

SELECT
    SUM(CAST(hired     AS INT))                     AS total_hired,
    SUM(CAST(rejected  AS INT))                     AS total_rejected,
    SUM(CAST(withdrawn AS INT))                     AS total_withdrawn,
    AVG(CASE WHEN hired = 1 THEN days_to_hire END)  AS avg_days_to_hire,
    AVG(CASE WHEN hired = 1 THEN days_to_offer END) AS avg_days_to_offer,
    AVG(CASE WHEN hired = 1
             THEN avg_performance_rating END)       AS avg_quality_of_hire
FROM gold.fact_applications

SELECT
    source_name,
    source_category,
    COUNT(*)                                        AS total_applications,
    SUM(CAST(hired AS INT))                         AS total_hires,
    CAST(SUM(CAST(hired AS INT)) AS FLOAT)
        / COUNT(*) * 100                            AS conversion_rate_pct
FROM gold.fact_applications
GROUP BY source_name, source_category
ORDER BY total_applications DESC