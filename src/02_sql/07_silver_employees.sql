IF OBJECT_ID('silver.employees', 'U') IS NOT NULL
    DROP TABLE silver.employees
GO

SELECT
    employee_id,
    first_name,
    last_name,
    LOWER(TRIM(email)) AS email,
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
    END AS department_canonical,

    sub_department,
    job_title,
    job_level,
    employment_type,

    TRY_CONVERT(DATE, hire_date,        23) AS hire_date,
    TRY_CONVERT(DATE, start_date,       23) AS start_date,
    TRY_CONVERT(DATE, termination_date, 23) AS termination_date,

    manager_id,

    CASE
        WHEN LOWER(TRIM(location_city)) IN ('remote','remote - europe','remote-europe')
        THEN NULL
        ELSE TRIM(location_city)
    END AS location_city,

    CASE
        WHEN LOWER(TRIM(location_city)) IN ('remote','remote - europe','remote-europe')
        THEN TRIM(location_country)
        WHEN TRIM(location_country) NOT IN ('','nan','None')
         AND location_country IS NOT NULL
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
    END AS location_country,

    CAST(
        CASE
            WHEN LOWER(TRIM(location_city)) IN ('remote','remote - europe','remote-europe')
            THEN 1 ELSE 0
        END
    AS BIT) AS is_remote,

    CASE
        WHEN LOWER(TRIM(salary_type)) = 'monthly'
        THEN TRY_CAST(salary_amount AS DECIMAL(12,2)) * 12
        WHEN LOWER(TRIM(salary_type)) = 'annual'
         AND employment_type = 'full_time'
         AND TRY_CAST(salary_amount AS DECIMAL(12,2)) < 10000
        THEN TRY_CAST(salary_amount AS DECIMAL(12,2)) * 12
        ELSE TRY_CAST(salary_amount AS DECIMAL(12,2))
    END AS salary_amount,

    CASE
        WHEN LOWER(TRIM(salary_type)) = 'monthly'
        THEN 'MONTHLY_CONVERTED'
        WHEN LOWER(TRIM(salary_type)) = 'annual'
         AND employment_type = 'full_time'
         AND TRY_CAST(salary_amount AS DECIMAL(12,2)) < 10000
        THEN 'PROBABLE_MONTHLY_CONVERTED'
        ELSE ''
    END AS salary_dq_flag,

    'annual'        AS salary_type,
    salary_currency,
    gender,
    nationality,
    status,

    -- NULL is now caught correctly (DQ-HRIS-05)
    CASE
        WHEN status = 'terminated'
         AND termination_reason IS NULL
        THEN 'unknown'
        ELSE termination_reason
    END AS termination_reason,

    ats_candidate_id,

    -- NULL is now caught correctly (DQ-HRIS-04)
    CAST(
        CASE
            WHEN TRY_CONVERT(DATE, start_date, 23) < '2024-01-01'
             AND ats_candidate_id IS NULL
            THEN 1 ELSE 0
        END
    AS BIT) AS pre_ats

INTO silver.employees
FROM bronze.peoplecore_employees
GO

-- Validation
SELECT 'bronze' AS layer, COUNT(*) AS row_count FROM bronze.peoplecore_employees
UNION ALL
SELECT 'silver',           COUNT(*)               FROM silver.employees

SELECT pre_ats,    COUNT(*) AS row_count FROM silver.employees GROUP BY pre_ats
SELECT salary_dq_flag, COUNT(*) AS row_count FROM silver.employees GROUP BY salary_dq_flag
SELECT termination_reason, COUNT(*) AS row_count
FROM silver.employees WHERE status = 'terminated'
GROUP BY termination_reason ORDER BY row_count DESC