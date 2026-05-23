-- =============================================================
-- STORED PROCEDURE: silver.load_all
-- Truncates and reloads all 9 silver tables from bronze.
-- Order matters: applications references candidates,
-- so candidates must load before applications.
-- =============================================================

CREATE OR ALTER PROCEDURE silver.load_all
AS
BEGIN
    SET NOCOUNT ON

    -- jobs
    IF OBJECT_ID('silver.jobs', 'U') IS NOT NULL
        TRUNCATE TABLE silver.jobs

    INSERT INTO silver.jobs
    SELECT
        job_id,
        job_title,
        department,
        location,
        employment_type,
        TRY_CONVERT(DATE, requisition_open_date,  23),
        TRY_CONVERT(DATE, requisition_close_date, 23),
        TRY_CONVERT(DATE, target_fill_date,       23),
        hiring_manager_id,
        recruiter_id,
        TRY_CAST(headcount_approved AS INT),
        LOWER(TRIM(status)),
        job_level,
        CASE
            WHEN LOWER(TRIM(status)) = 'open'
             AND TRY_CONVERT(DATE, requisition_open_date, 23) < DATEADD(DAY, -120, GETDATE())
            THEN 'POSSIBLY_UNCLOSED'
            ELSE ''
        END
    FROM bronze.talentflow_jobs

    -- candidates
    IF OBJECT_ID('silver.candidates', 'U') IS NOT NULL
        TRUNCATE TABLE silver.candidates

    INSERT INTO silver.candidates
    SELECT
        candidate_id,
        first_name,
        last_name,
        LOWER(TRIM(email)),
        phone,
        location_city,
        location_country,
        current_company,
        current_title,
        linkedin_url,
        TRY_CONVERT(DATE, created_date, 23),
        CASE
            WHEN LOWER(TRIM(email)) IN (
                SELECT LOWER(TRIM(email))
                FROM bronze.talentflow_candidates
                GROUP BY LOWER(TRIM(email))
                HAVING COUNT(*) > 1
            )
            THEN 'PROBABLE_DUPLICATE'
            ELSE ''
        END
    FROM bronze.talentflow_candidates

    -- applications
    IF OBJECT_ID('silver.applications', 'U') IS NOT NULL
        TRUNCATE TABLE silver.applications

    INSERT INTO silver.applications
    SELECT
        application_id,
        candidate_id,
        job_id,
        CASE
            WHEN LOWER(TRIM(source)) IN ('linkedin organic','linkedin','linked in',
                 'li','linkedin jobs','linkedin.com')
                THEN 'LinkedIn Organic'
            WHEN LOWER(TRIM(source)) IN ('linkedin paid','linkedin sponsored',
                 'linkedin ads','linkedin paid job')
                THEN 'LinkedIn Paid'
            WHEN LOWER(TRIM(source)) IN ('linkedin recruiter','li recruiter',
                 'linkedin inmail','linkedin inmails')
                THEN 'LinkedIn Recruiter'
            WHEN LOWER(TRIM(source)) IN ('employee referral','referral',
                 'internal referral','ee referral','employee ref')
                THEN 'Employee Referral'
            WHEN LOWER(TRIM(source)) IN ('direct application','direct',
                 'careers page','company website','careers site')
                THEN 'Direct Application'
            WHEN LOWER(TRIM(source)) IN ('indeed','indeed.com')
                THEN 'Indeed'
            WHEN LOWER(TRIM(source)) IN ('glassdoor','glassdoor.com')
                THEN 'Glassdoor'
            WHEN LOWER(TRIM(source)) IN ('recruitment agency','agency',
                 'external recruiter','headhunter')
                THEN 'Recruitment Agency'
            WHEN LOWER(TRIM(source)) IN ('github sourcing','github')
                THEN 'GitHub Sourcing'
            WHEN LOWER(TRIM(source)) IN ('university partnership')
                THEN 'University Partnership'
            ELSE 'Other'
        END,
        source_subtype,
        COALESCE(
            TRY_CONVERT(DATE, application_date, 23),
            TRY_CONVERT(DATE, application_date, 103),
            TRY_CONVERT(DATE, application_date, 101)
        ),
        COALESCE(
            TRY_CONVERT(DATE, current_stage_date, 23),
            TRY_CONVERT(DATE, current_stage_date, 103),
            TRY_CONVERT(DATE, current_stage_date, 101)
        ),
        current_stage,
        CAST(CASE WHEN LOWER(TRIM(hired))    = 'true' THEN 1 ELSE 0 END AS BIT),
        CAST(CASE WHEN LOWER(TRIM(rejected)) = 'true' THEN 1 ELSE 0 END AS BIT),
        CAST(CASE WHEN LOWER(TRIM(withdrawn))= 'true' THEN 1 ELSE 0 END AS BIT)
    FROM bronze.talentflow_applications

    -- pipeline_events
    IF OBJECT_ID('silver.pipeline_events', 'U') IS NOT NULL
        TRUNCATE TABLE silver.pipeline_events

    INSERT INTO silver.pipeline_events
    SELECT
        event_id,
        application_id,
        CASE
            WHEN LOWER(TRIM(from_stage)) IN ('phone screen','phone_screen',
                 'phone interview','recruiter call','recruiter_screen','recruiter screen')
                THEN 'Recruiter Screen'
            WHEN LOWER(TRIM(from_stage)) IN ('hm screen','hm call',
                 'hiring_manager_screen','manager screen','hiring manager screen')
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
        END,
        CASE
            WHEN LOWER(TRIM(to_stage)) IN ('phone screen','phone_screen',
                 'phone interview','recruiter call','recruiter_screen','recruiter screen')
                THEN 'Recruiter Screen'
            WHEN LOWER(TRIM(to_stage)) IN ('hm screen','hm call',
                 'hiring_manager_screen','manager screen','hiring manager screen')
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
        END,
        COALESCE(
            TRY_CONVERT(DATE, event_date, 23),
            TRY_CONVERT(DATE, event_date, 103),
            TRY_CONVERT(DATE, event_date, 101)
        ),
        event_type,
        CASE
            WHEN rejection_reason IS NULL
             AND LOWER(TRIM(event_type)) = 'rejected'
            THEN 'REASON_NOT_RECORDED'
            ELSE rejection_reason
        END,
        interviewer_id,
        notes,
        '',  -- dq_date_sequence_flag placeholder
        ''   -- dq_stage_skip_flag placeholder
    FROM bronze.talentflow_pipeline_events

    -- Update date sequence flags
    UPDATE e
    SET e.dq_date_sequence_flag = 'DATE_SEQUENCE_ERROR'
    FROM silver.pipeline_events e
    WHERE EXISTS (
        SELECT 1
        FROM silver.pipeline_events prev
        WHERE prev.application_id = e.application_id
          AND prev.event_date > e.event_date
          AND prev.event_id < e.event_id
    )

    -- offers
    IF OBJECT_ID('silver.offers', 'U') IS NOT NULL
        TRUNCATE TABLE silver.offers

    INSERT INTO silver.offers
    SELECT
        offer_id,
        application_id,
        TRY_CONVERT(DATE, offer_date,    23),
        TRY_CONVERT(DATE, accepted_date, 23),
        TRY_CAST(
            CASE
                WHEN LOWER(TRIM(
                        REPLACE(REPLACE(REPLACE(REPLACE(
                        offer_amount,'EUR',''),'euro',''),'€',''),' ','')))
                     LIKE '%k'
                THEN CAST(TRY_CAST(
                        LEFT(LOWER(TRIM(REPLACE(REPLACE(REPLACE(REPLACE(
                        offer_amount,'EUR',''),'euro',''),'€',''),' ',''))),
                        LEN(LOWER(TRIM(REPLACE(REPLACE(REPLACE(REPLACE(
                        offer_amount,'EUR',''),'euro',''),'€',''),' ',''))))-1)
                     AS DECIMAL(12,2)) * 1000 AS VARCHAR(20))
                WHEN REPLACE(REPLACE(REPLACE(REPLACE(
                        offer_amount,'EUR',''),'euro',''),'€',''),' ','')
                     LIKE '[0-9][0-9].[0-9][0-9][0-9]'
                  OR REPLACE(REPLACE(REPLACE(REPLACE(
                        offer_amount,'EUR',''),'euro',''),'€',''),' ','')
                     LIKE '[0-9][0-9][0-9].[0-9][0-9][0-9]'
                THEN REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                        offer_amount,'EUR',''),'euro',''),'€',''),' ',''),'.','')
                WHEN REPLACE(REPLACE(REPLACE(REPLACE(
                        offer_amount,'EUR',''),'euro',''),'€',''),' ','')
                     LIKE '%,%'
                THEN REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                        offer_amount,'EUR',''),'euro',''),'€',''),' ',''),',','')
                ELSE REPLACE(REPLACE(REPLACE(REPLACE(
                        offer_amount,'EUR',''),'euro',''),'€',''),' ','')
            END
        AS DECIMAL(12,2)),
        offer_currency,
        CAST(CASE WHEN LOWER(TRIM(equity_offered)) = 'true' THEN 1 ELSE 0 END AS BIT),
        offer_status,
        decline_reason
    FROM bronze.talentflow_offers

    -- employees
    IF OBJECT_ID('silver.employees', 'U') IS NOT NULL
        TRUNCATE TABLE silver.employees

    INSERT INTO silver.employees
    SELECT
        employee_id, first_name, last_name,
        LOWER(TRIM(email)),
        department,
        CASE TRIM(department)
            WHEN 'Engineering' THEN 'Technology'
            WHEN 'Product'     THEN 'Product'
            WHEN 'Analytics'   THEN 'Data and Analytics'
            WHEN 'Growth'      THEN 'Commercial'
            WHEN 'Finance'     THEN 'Finance'
            WHEN 'Operations'  THEN 'Operations'
            WHEN 'HR'          THEN 'People'
            WHEN 'Legal'       THEN 'Legal and Compliance'
            ELSE TRIM(department)
        END,
        sub_department, job_title, job_level, employment_type,
        TRY_CONVERT(DATE, hire_date,        23),
        TRY_CONVERT(DATE, start_date,       23),
        TRY_CONVERT(DATE, termination_date, 23),
        manager_id,
        CASE
            WHEN LOWER(TRIM(location_city)) IN ('remote','remote - europe','remote-europe')
            THEN NULL ELSE TRIM(location_city)
        END,
        CASE
            WHEN LOWER(TRIM(location_city)) IN ('remote','remote - europe','remote-europe')
            THEN TRIM(location_country)
            WHEN location_country IS NOT NULL
             AND TRIM(location_country) NOT IN ('','nan','None')
            THEN TRIM(location_country)
            ELSE
                CASE LOWER(TRIM(location_city))
                    WHEN 'vilnius'   THEN 'Lithuania'
                    WHEN 'kaunas'    THEN 'Lithuania'
                    WHEN 'warsaw'    THEN 'Poland'
                    WHEN 'krakow'    THEN 'Poland'
                    WHEN 'berlin'    THEN 'Germany'
                    WHEN 'amsterdam' THEN 'Netherlands'
                    WHEN 'london'    THEN 'United Kingdom'
                    WHEN 'tallinn'   THEN 'Estonia'
                    WHEN 'riga'      THEN 'Latvia'
                    WHEN 'kyiv'      THEN 'Ukraine'
                    ELSE 'LOCATION_UNKNOWN'
                END
        END,
        CAST(CASE
            WHEN LOWER(TRIM(location_city)) IN ('remote','remote - europe','remote-europe')
            THEN 1 ELSE 0
        END AS BIT),
        CASE
            WHEN LOWER(TRIM(salary_type)) = 'monthly'
            THEN TRY_CAST(salary_amount AS DECIMAL(12,2)) * 12
            WHEN LOWER(TRIM(salary_type)) = 'annual'
             AND employment_type = 'full_time'
             AND TRY_CAST(salary_amount AS DECIMAL(12,2)) < 10000
            THEN TRY_CAST(salary_amount AS DECIMAL(12,2)) * 12
            ELSE TRY_CAST(salary_amount AS DECIMAL(12,2))
        END,
        CASE
            WHEN LOWER(TRIM(salary_type)) = 'monthly'
            THEN 'MONTHLY_CONVERTED'
            WHEN LOWER(TRIM(salary_type)) = 'annual'
             AND employment_type = 'full_time'
             AND TRY_CAST(salary_amount AS DECIMAL(12,2)) < 10000
            THEN 'PROBABLE_MONTHLY_CONVERTED'
            ELSE ''
        END,
        'annual',
        salary_currency, gender, nationality, status,
        CASE
            WHEN status = 'terminated' AND termination_reason IS NULL
            THEN 'unknown'
            ELSE termination_reason
        END,
        ats_candidate_id,
        CAST(CASE
            WHEN TRY_CONVERT(DATE, start_date, 23) < '2024-01-01'
             AND ats_candidate_id IS NULL
            THEN 1 ELSE 0
        END AS BIT)
    FROM bronze.peoplecore_employees

    -- performance
    IF OBJECT_ID('silver.performance', 'U') IS NOT NULL
        TRUNCATE TABLE silver.performance

    INSERT INTO silver.performance
    SELECT
        review_id, employee_id, review_period,
        TRY_CAST(rating AS INT),
        reviewer_id,
        TRY_CONVERT(DATE, submitted_date, 23)
    FROM bronze.peoplecore_performance

    -- compensation
    IF OBJECT_ID('silver.compensation', 'U') IS NOT NULL
        TRUNCATE TABLE silver.compensation

    INSERT INTO silver.compensation
    SELECT
        change_id, employee_id,
        TRY_CONVERT(DATE, change_date, 23),
        TRY_CAST(old_salary AS DECIMAL(12,2)),
        TRY_CAST(new_salary AS DECIMAL(12,2)),
        change_reason
    FROM bronze.peoplecore_compensation

    -- headcount_plan
    IF OBJECT_ID('silver.headcount_plan', 'U') IS NOT NULL
        TRUNCATE TABLE silver.headcount_plan

    INSERT INTO silver.headcount_plan
    SELECT
        plan_id, department,
        CASE TRIM(department)
            WHEN 'Engineering & Product' THEN 'Technology / Product'
            WHEN 'Analytics'             THEN 'Data and Analytics'
            WHEN 'Sales & Marketing'     THEN 'Commercial'
            WHEN 'Finance'               THEN 'Finance'
            WHEN 'Operations'            THEN 'Operations'
            WHEN 'HR & Legal'            THEN 'People / Legal and Compliance'
            ELSE TRIM(department)
        END,
        quarter,
        TRY_CAST(TRY_CAST(headcount_approved AS DECIMAL(10,1)) AS INT),
        TRY_CAST(TRY_CAST(headcount_actual   AS DECIMAL(10,1)) AS INT),
        CASE
            WHEN TRIM(department) = 'Engineering & Product'
             AND TRIM(quarter)    = 'Q2_2024'
            THEN 7 ELSE 0
        END,
        CASE
            WHEN TRIM(department) = 'Engineering & Product'
             AND TRIM(quarter)    = 'Q2_2024'
            THEN TRY_CAST(TRY_CAST(headcount_approved AS DECIMAL(10,1)) AS INT) + 7
            ELSE TRY_CAST(TRY_CAST(headcount_approved AS DECIMAL(10,1)) AS INT)
        END,
        notes,
        CASE
            WHEN headcount_approved IS NULL THEN 'PLAN_NOT_SUBMITTED'
            ELSE ''
        END
    FROM bronze.finance_headcount_plan

    -- Return row counts for logging
    SELECT
        (SELECT COUNT(*) FROM silver.jobs)           AS jobs,
        (SELECT COUNT(*) FROM silver.candidates)     AS candidates,
        (SELECT COUNT(*) FROM silver.applications)   AS applications,
        (SELECT COUNT(*) FROM silver.pipeline_events) AS pipeline_events,
        (SELECT COUNT(*) FROM silver.offers)         AS offers,
        (SELECT COUNT(*) FROM silver.employees)      AS employees,
        (SELECT COUNT(*) FROM silver.performance)    AS performance,
        (SELECT COUNT(*) FROM silver.compensation)   AS compensation,
        (SELECT COUNT(*) FROM silver.headcount_plan) AS headcount_plan

END
GO

-- Test it
EXEC silver.load_all