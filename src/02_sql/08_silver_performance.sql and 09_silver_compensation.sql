-- =============================================================
-- SILVER LAYER: performance and compensation
-- Source: bronze.peoplecore_performance
--         bronze.peoplecore_compensation
--
-- Changes from bronze:
--   performance:   submitted_date cast to DATE, rating to INT
--   compensation:  change_date cast to DATE,
--                  salary columns cast to DECIMAL
-- =============================================================

IF OBJECT_ID('silver.performance', 'U') IS NOT NULL
    DROP TABLE silver.performance
GO

SELECT
    review_id,
    employee_id,
    review_period,
    TRY_CAST(rating AS INT)                    AS rating,
    reviewer_id,
    TRY_CONVERT(DATE, submitted_date, 23)      AS submitted_date
INTO silver.performance
FROM bronze.peoplecore_performance
GO

IF OBJECT_ID('silver.compensation', 'U') IS NOT NULL
    DROP TABLE silver.compensation
GO

SELECT
    change_id,
    employee_id,
    TRY_CONVERT(DATE, change_date, 23)         AS change_date,
    TRY_CAST(old_salary AS DECIMAL(12,2))      AS old_salary,
    TRY_CAST(new_salary AS DECIMAL(12,2))      AS new_salary,
    change_reason
INTO silver.compensation
FROM bronze.peoplecore_compensation
GO

-- =============================================================
-- VALIDATION
-- =============================================================

SELECT 'bronze_performance' AS layer, COUNT(*) AS row_count
FROM bronze.peoplecore_performance
UNION ALL
SELECT 'silver_performance', COUNT(*) FROM silver.performance
UNION ALL
SELECT 'bronze_compensation', COUNT(*) FROM bronze.peoplecore_compensation
UNION ALL
SELECT 'silver_compensation', COUNT(*) FROM silver.compensation

SELECT
    MIN(rating) AS min_rating,
    MAX(rating) AS max_rating,
    AVG(CAST(rating AS FLOAT)) AS avg_rating,
    SUM(CASE WHEN rating IS NULL THEN 1 ELSE 0 END) AS null_ratings
FROM silver.performance

SELECT
    MIN(old_salary) AS min_old_salary,
    MAX(new_salary) AS max_new_salary,
    AVG(new_salary - old_salary) AS avg_increase,
    SUM(CASE WHEN old_salary IS NULL OR new_salary IS NULL
             THEN 1 ELSE 0 END) AS null_salaries
FROM silver.compensation