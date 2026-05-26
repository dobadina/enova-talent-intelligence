-- =============================================================
-- SECTION 1A: Overall hiring funnel
-- How many applications, how many converted, at what rate
-- =============================================================

SELECT
    COUNT(*)                                        AS total_applications,
    SUM(CAST(hired     AS INT))                     AS total_hires,
    SUM(CAST(rejected  AS INT))                     AS total_rejected,
    SUM(CAST(withdrawn AS INT))                     AS total_withdrawn,
    CAST(SUM(CAST(hired AS INT)) AS FLOAT)
        / COUNT(*) * 100                            AS conversion_rate_pct,
    AVG(CASE WHEN hired = 1
             AND days_to_hire > 0
             AND days_to_hire < 365
             THEN days_to_hire END)                 AS avg_days_to_hire,
    AVG(CASE WHEN hired = 1
             THEN avg_performance_rating END)       AS avg_quality_of_hire
FROM gold.fact_applications


-- =============================================================
-- SECTION 1B: Hiring funnel by department
-- Which departments are hardest to hire for
-- Ordered by conversion rate ascending so problem depts
-- appear at the top
-- =============================================================

SELECT
    department,
    COUNT(*)                                        AS total_applications,
    SUM(CAST(hired AS INT))                         AS total_hires,
    SUM(CAST(rejected AS INT))                      AS total_rejected,
    SUM(CAST(withdrawn AS INT))                     AS total_withdrawn,
    CAST(SUM(CAST(hired AS INT)) AS FLOAT)
        / COUNT(*) * 100                            AS conversion_rate_pct,
    AVG(CASE WHEN hired = 1
             AND days_to_hire > 0
             AND days_to_hire < 365
             THEN days_to_hire END)                 AS avg_days_to_hire,
    AVG(CASE WHEN hired = 1
             THEN avg_performance_rating END)       AS avg_quality_of_hire,
    COUNT(DISTINCT job_title)                       AS distinct_roles_hired
FROM gold.fact_applications
GROUP BY department
ORDER BY conversion_rate_pct ASC


-- =============================================================
-- SECTION 1C: Hiring funnel by job level
-- Where in the seniority ladder is hiring hardest
-- =============================================================

SELECT
    job_level,
    COUNT(*)                                        AS total_applications,
    SUM(CAST(hired AS INT))                         AS total_hires,
    CAST(SUM(CAST(hired AS INT)) AS FLOAT)
        / COUNT(*) * 100                            AS conversion_rate_pct,
    AVG(CASE WHEN hired = 1
             AND days_to_hire > 0
             AND days_to_hire < 365
             THEN days_to_hire END)                 AS avg_days_to_hire,
    AVG(CASE WHEN hired = 1
             THEN avg_performance_rating END)       AS avg_quality_of_hire
FROM gold.fact_applications
WHERE job_level IS NOT NULL
GROUP BY job_level
ORDER BY
    CASE job_level
        WHEN 'ic1'            THEN 1
        WHEN 'ic2'            THEN 2
        WHEN 'ic3'            THEN 3
        WHEN 'manager'        THEN 4
        WHEN 'senior_manager' THEN 5
        WHEN 'director'       THEN 6
        WHEN 'vp'             THEN 7
    END-- =============================================================
-- SECTION 1C: Hiring funnel by job level
-- Where in the seniority ladder is hiring hardest
-- =============================================================

SELECT
    job_level,
    COUNT(*)                                        AS total_applications,
    SUM(CAST(hired AS INT))                         AS total_hires,
    CAST(SUM(CAST(hired AS INT)) AS FLOAT)
        / COUNT(*) * 100                            AS conversion_rate_pct,
    AVG(CASE WHEN hired = 1
             AND days_to_hire > 0
             AND days_to_hire < 365
             THEN days_to_hire END)                 AS avg_days_to_hire,
    AVG(CASE WHEN hired = 1
             THEN avg_performance_rating END)       AS avg_quality_of_hire
FROM gold.fact_applications
WHERE job_level IS NOT NULL
GROUP BY job_level
ORDER BY
    CASE job_level
        WHEN 'ic1'            THEN 1
        WHEN 'ic2'            THEN 2
        WHEN 'ic3'            THEN 3
        WHEN 'manager'        THEN 4
        WHEN 'senior_manager' THEN 5
        WHEN 'director'       THEN 6
        WHEN 'vp'             THEN 7
    END


-- =============================================================
-- SECTION 2A: Source effectiveness
-- Which channels produce the best candidates
-- The three dimensions that matter: volume, conversion, quality
-- =============================================================

SELECT
    source_name,
    source_category,
    COUNT(*)                                        AS total_applications,
    CAST(COUNT(*) AS FLOAT)
        / SUM(COUNT(*)) OVER () * 100               AS pct_of_applications,
    SUM(CAST(hired AS INT))                         AS total_hires,
    CAST(SUM(CAST(hired AS INT)) AS FLOAT)
        / SUM(SUM(CAST(hired AS INT))) OVER () * 100 AS pct_of_hires,
    CAST(SUM(CAST(hired AS INT)) AS FLOAT)
        / COUNT(*) * 100                            AS conversion_rate_pct,
    AVG(CASE WHEN hired = 1
             AND days_to_hire > 0
             AND days_to_hire < 365
             THEN days_to_hire END)                 AS avg_days_to_hire,
    AVG(CASE WHEN hired = 1
             THEN avg_performance_rating END)       AS avg_quality_of_hire
FROM gold.fact_applications
WHERE source_name IS NOT NULL
GROUP BY source_name, source_category
ORDER BY conversion_rate_pct DESC


-- =============================================================
-- SECTION 2B: Source effectiveness by department
-- Does the referral advantage hold across all departments
-- or is it concentrated in specific teams
-- =============================================================

SELECT
    department,
    source_name,
    COUNT(*)                                        AS total_applications,
    SUM(CAST(hired AS INT))                         AS total_hires,
    CAST(SUM(CAST(hired AS INT)) AS FLOAT)
        / COUNT(*) * 100                            AS conversion_rate_pct,
    AVG(CASE WHEN hired = 1
             AND days_to_hire > 0
             AND days_to_hire < 365
             THEN days_to_hire END)                 AS avg_days_to_hire,
    AVG(CASE WHEN hired = 1
             THEN avg_performance_rating END)       AS avg_quality_of_hire
FROM gold.fact_applications
WHERE source_name IN (
    'Employee Referral',
    'LinkedIn Recruiter',
    'LinkedIn Organic',
    'Recruitment Agency'
)
GROUP BY department, source_name
HAVING COUNT(*) >= 5
ORDER BY department, conversion_rate_pct DESC


-- =============================================================
-- SECTION 3A: Average days in each pipeline stage
-- Where is time being lost in the hiring process
-- Excludes flagged sequence errors and stage skips
-- =============================================================

WITH stage_stats AS (
    SELECT
        to_stage                                    AS stage,
        COUNT(*)                                    AS total_events,
        AVG(CAST(days_in_stage AS FLOAT))           AS avg_days_in_stage,
        MIN(days_in_stage)                          AS min_days,
        MAX(days_in_stage)                          AS max_days,
        STDEV(CAST(days_in_stage AS FLOAT))         AS stdev_days
    FROM gold.fact_pipeline_events
    WHERE days_in_stage IS NOT NULL
      AND days_in_stage >= 0
      AND days_in_stage < 60
      AND dq_date_sequence_flag = ''
      AND dq_stage_skip_flag    = ''
      AND to_stage NOT IN ('Applied', 'Hired', 'Offer Accepted')
    GROUP BY to_stage
),
stage_medians AS (
    SELECT DISTINCT
        to_stage                                    AS stage,
        PERCENTILE_CONT(0.5) WITHIN GROUP
            (ORDER BY days_in_stage)
            OVER (PARTITION BY to_stage)            AS median_days
    FROM gold.fact_pipeline_events
    WHERE days_in_stage IS NOT NULL
      AND days_in_stage >= 0
      AND days_in_stage < 60
      AND dq_date_sequence_flag = ''
      AND dq_stage_skip_flag    = ''
      AND to_stage NOT IN ('Applied', 'Hired', 'Offer Accepted')
)
SELECT
    s.stage,
    s.total_events,
    ROUND(s.avg_days_in_stage, 1)                   AS avg_days_in_stage,
    ROUND(m.median_days, 1)                         AS median_days,
    s.min_days,
    s.max_days,
    ROUND(s.stdev_days, 1)                          AS stdev_days
FROM stage_stats s
JOIN stage_medians m ON m.stage = s.stage
ORDER BY avg_days_in_stage DESC


-- =============================================================
-- SECTION 3B: Technical Assessment duration by department
-- Confirms whether the bottleneck is concentrated in
-- specific departments or spread across all technical roles
-- =============================================================

SELECT
    department,
    COUNT(*)                                        AS assessments,
    ROUND(AVG(CAST(days_in_stage AS FLOAT)), 1)     AS avg_days,
    ROUND(MIN(CAST(days_in_stage AS FLOAT)), 1)     AS min_days,
    ROUND(MAX(CAST(days_in_stage AS FLOAT)), 1)     AS max_days,
    ROUND(STDEV(CAST(days_in_stage AS FLOAT)), 1)   AS stdev_days,
    SUM(CASE WHEN days_in_stage > 7
             THEN 1 ELSE 0 END)                     AS over_7_days,
    ROUND(CAST(SUM(CASE WHEN days_in_stage > 7
             THEN 1 ELSE 0 END) AS FLOAT)
        / COUNT(*) * 100, 1)                        AS pct_over_7_days
FROM gold.fact_pipeline_events
WHERE to_stage = 'Technical Assessment'
  AND days_in_stage IS NOT NULL
  AND days_in_stage >= 0
  AND days_in_stage < 60
  AND dq_date_sequence_flag = ''
GROUP BY department
ORDER BY avg_days DESC


-- =============================================================
-- SECTION 4A: Time to hire by department
-- Full picture of hiring speed across the organisation
-- =============================================================

SELECT
    department,
    COUNT(*)                                        AS total_hires,
    ROUND(AVG(CAST(days_to_hire AS FLOAT)), 0)      AS avg_days_to_hire,
    ROUND(MIN(CAST(days_to_hire AS FLOAT)), 0)      AS min_days,
    ROUND(MAX(CAST(days_to_hire AS FLOAT)), 0)      AS max_days,
    ROUND(STDEV(CAST(days_to_hire AS FLOAT)), 0)    AS stdev_days,
    SUM(CASE WHEN days_to_hire > 60
             THEN 1 ELSE 0 END)                     AS hires_over_60_days,
    ROUND(CAST(SUM(CASE WHEN days_to_hire > 60
             THEN 1 ELSE 0 END) AS FLOAT)
        / COUNT(*) * 100, 1)                        AS pct_over_60_days
FROM gold.fact_applications
WHERE hired = 1
  AND days_to_hire > 0
  AND days_to_hire < 365
GROUP BY department
ORDER BY avg_days_to_hire DESC


-- =============================================================
-- SECTION 4B: Time to hire by recruiter
-- Identifies whether hiring speed varies across the
-- recruiting team or is driven by department/role factors
-- Recruiters anonymised by ID as per data governance
-- =============================================================

SELECT
    recruiter_id,
    COUNT(*)                                        AS total_hires,
    COUNT(DISTINCT department)                      AS departments_covered,
    ROUND(AVG(CAST(days_to_hire AS FLOAT)), 0)      AS avg_days_to_hire,
    ROUND(MIN(CAST(days_to_hire AS FLOAT)), 0)      AS min_days,
    ROUND(MAX(CAST(days_to_hire AS FLOAT)), 0)      AS max_days,
    ROUND(STDEV(CAST(days_to_hire AS FLOAT)), 0)    AS stdev_days,
    ROUND(AVG(CASE WHEN avg_performance_rating IS NOT NULL
              THEN avg_performance_rating END), 2)  AS avg_quality_of_hire,
    ROUND(CAST(COUNT(*) AS FLOAT)
        / SUM(COUNT(*)) OVER () * 100, 1)           AS pct_of_total_hires
FROM gold.fact_applications
WHERE hired = 1
  AND days_to_hire > 0
  AND days_to_hire < 365
  AND recruiter_id IS NOT NULL
GROUP BY recruiter_id
HAVING COUNT(*) >= 5
ORDER BY avg_days_to_hire ASC


-- =============================================================
-- SECTION 5A: Offer outcomes overview
-- Acceptance rate, decline reasons, and offer amounts
-- =============================================================

SELECT
    offer_status,
    COUNT(*)                                        AS total_offers,
    ROUND(CAST(COUNT(*) AS FLOAT)
        / SUM(COUNT(*)) OVER () * 100, 1)           AS pct_of_offers,
    ROUND(AVG(offer_amount), 0)                     AS avg_offer_amount,
    ROUND(MIN(offer_amount), 0)                     AS min_offer,
    ROUND(MAX(offer_amount), 0)                     AS max_offer
FROM gold.fact_offers
WHERE offer_amount IS NOT NULL
GROUP BY offer_status
ORDER BY total_offers DESC


-- =============================================================
-- SECTION 5B: Offer acceptance by department
-- Which departments struggle to close candidates
-- =============================================================

SELECT
    f.department,
    COUNT(*)                                            AS total_offers,
    SUM(CAST(f.is_accepted AS INT))                     AS offers_accepted,
    ROUND(CAST(SUM(CAST(f.is_accepted AS INT)) AS FLOAT)
        / COUNT(*) * 100, 1)                            AS acceptance_rate_pct,
    ROUND(AVG(CASE WHEN f.offer_status = 'accepted'
              THEN f.offer_amount END), 0)              AS avg_accepted_amount,
    ROUND(AVG(CASE WHEN f.offer_status = 'declined'
              THEN f.offer_amount END), 0)              AS avg_declined_amount,
    ROUND(AVG(CASE WHEN f.offer_status = 'accepted'
              THEN f.offer_amount END)
        - AVG(CASE WHEN f.offer_status = 'declined'
              THEN f.offer_amount END), 0)              AS accepted_vs_declined_gap,
    COUNT(CASE WHEN f.offer_status = 'declined'
               THEN 1 END)                              AS declines,
    COUNT(CASE WHEN f.offer_status = 'expired'
               THEN 1 END)                              AS expired
FROM gold.fact_offers f
WHERE f.department IS NOT NULL
GROUP BY f.department
HAVING COUNT(*) >= 3
ORDER BY acceptance_rate_pct ASC


-- =============================================================
-- SECTION 6A: Headcount vs plan overview
-- How well has actual hiring tracked against Finance targets
-- =============================================================

SELECT
    finance_department,
    quarter,
    headcount_total_approved,
    headcount_actual,
    headcount_variance,
    ROUND(headcount_variance_pct, 1)                AS variance_pct,
    headcount_emergency_approved,
    dq_plan_flag
FROM gold.fact_headcount
WHERE headcount_total_approved IS NOT NULL
ORDER BY finance_department, quarter


-- =============================================================
-- SECTION 6B: Headcount variance trend over time
-- Shows the shift from over-plan to under-plan
-- =============================================================

SELECT
    quarter,
    SUM(headcount_total_approved)                   AS total_approved,
    SUM(headcount_actual)                           AS total_actual,
    SUM(headcount_variance)                         AS total_variance,
    ROUND(
        CAST(SUM(headcount_variance) AS FLOAT)
        / SUM(headcount_total_approved) * 100
    , 1)                                            AS overall_variance_pct,
    SUM(CASE WHEN headcount_variance > 0
             THEN 1 ELSE 0 END)                     AS depts_above_plan,
    SUM(CASE WHEN headcount_variance < 0
             THEN 1 ELSE 0 END)                     AS depts_below_plan,
    SUM(CASE WHEN headcount_variance = 0
             THEN 1 ELSE 0 END)                     AS depts_on_plan
FROM gold.fact_headcount
WHERE headcount_total_approved IS NOT NULL
GROUP BY quarter
ORDER BY quarter


-- =============================================================
-- SECTION 7A: Attrition overview
-- Overall rate, voluntary vs involuntary split,
-- and distribution by department
-- =============================================================

WITH tenure_bands AS (
    SELECT
        employee_id,
        department,
        status,
        termination_reason,
        DATEDIFF(MONTH,
            TRY_CONVERT(DATE, start_date, 23),
            CASE WHEN status = 'terminated'
                 THEN TRY_CONVERT(DATE, termination_date, 23)
                 ELSE CAST('2025-07-01' AS DATE)
            END)                                    AS tenure_months,
        CASE
            WHEN DATEDIFF(MONTH,
                TRY_CONVERT(DATE, start_date, 23),
                CAST('2025-07-01' AS DATE)) <= 6    THEN '0-6 months'
            WHEN DATEDIFF(MONTH,
                TRY_CONVERT(DATE, start_date, 23),
                CAST('2025-07-01' AS DATE)) <= 12   THEN '7-12 months'
            WHEN DATEDIFF(MONTH,
                TRY_CONVERT(DATE, start_date, 23),
                CAST('2025-07-01' AS DATE)) <= 24   THEN '13-24 months'
            ELSE '24+ months'
        END                                         AS tenure_band
    FROM silver.employees
)
SELECT
    department,
    COUNT(*)                                        AS total_employees,
    SUM(CASE WHEN status = 'terminated'
             THEN 1 ELSE 0 END)                     AS total_terminated,
    ROUND(CAST(SUM(CASE WHEN status = 'terminated'
             THEN 1 ELSE 0 END) AS FLOAT)
        / COUNT(*) * 100, 1)                        AS attrition_rate_pct,
    SUM(CASE WHEN termination_reason = 'voluntary_resignation'
             THEN 1 ELSE 0 END)                     AS voluntary,
    SUM(CASE WHEN termination_reason IN (
                 'involuntary_performance',
                 'involuntary_restructuring')
             THEN 1 ELSE 0 END)                     AS involuntary,
    SUM(CASE WHEN termination_reason = 'unknown'
             THEN 1 ELSE 0 END)                     AS unknown_reason,
    ROUND(AVG(CAST(tenure_months AS FLOAT)), 1)     AS avg_tenure_months
FROM tenure_bands
GROUP BY department
ORDER BY attrition_rate_pct DESC


-- =============================================================
-- SECTION 7B: Attrition by tenure band
-- When in the employee lifecycle is attrition highest
-- Early attrition (0-12 months) signals onboarding or
-- role fit issues. Late attrition signals compensation
-- or career progression issues.
-- =============================================================

WITH tenure_calc AS (
    SELECT
        employee_id,
        department,
        status,
        termination_reason,
        DATEDIFF(MONTH,
            TRY_CONVERT(DATE, start_date, 23),
            CASE WHEN status = 'terminated'
                 THEN TRY_CONVERT(DATE, termination_date, 23)
                 ELSE CAST('2025-07-01' AS DATE)
            END)                                    AS tenure_at_exit_months
    FROM silver.employees
    WHERE status = 'terminated'
      AND termination_reason != 'unknown'
),
bands AS (
    SELECT
        employee_id,
        department,
        termination_reason,
        tenure_at_exit_months,
        CASE
            WHEN tenure_at_exit_months <= 6   THEN '0-6 months'
            WHEN tenure_at_exit_months <= 12  THEN '7-12 months'
            WHEN tenure_at_exit_months <= 24  THEN '13-24 months'
            ELSE '25+ months'
        END                                         AS tenure_band,
        CASE
            WHEN tenure_at_exit_months <= 6   THEN 1
            WHEN tenure_at_exit_months <= 12  THEN 2
            WHEN tenure_at_exit_months <= 24  THEN 3
            ELSE 4
        END                                         AS band_order
    FROM tenure_calc
)
SELECT
    tenure_band,
    COUNT(*)                                        AS terminations,
    ROUND(CAST(COUNT(*) AS FLOAT)
        / SUM(COUNT(*)) OVER () * 100, 1)           AS pct_of_terminations,
    SUM(CASE WHEN termination_reason = 'voluntary_resignation'
             THEN 1 ELSE 0 END)                     AS voluntary,
    SUM(CASE WHEN termination_reason IN (
                 'involuntary_performance',
                 'involuntary_restructuring')
             THEN 1 ELSE 0 END)                     AS involuntary,
    ROUND(AVG(CAST(tenure_at_exit_months AS FLOAT)),1) AS avg_tenure_months
FROM bands
GROUP BY tenure_band, band_order
ORDER BY band_order