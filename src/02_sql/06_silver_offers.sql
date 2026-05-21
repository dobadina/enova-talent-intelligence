-- =============================================================
-- SILVER LAYER: offers
-- Source: bronze.talentflow_offers
--
-- Changes from bronze:
--   1. offer_amount parsed from mixed text/numeric to DECIMAL
--      Handles EUR prefix, k suffix, European decimal format
--   2. Date columns cast to DATE
--   3. equity_offered cast to BIT
-- =============================================================

IF OBJECT_ID('silver.offers', 'U') IS NOT NULL
    DROP TABLE silver.offers
GO

SELECT
    offer_id,
    application_id,

    TRY_CONVERT(DATE, offer_date,    23) AS offer_date,
    TRY_CONVERT(DATE, accepted_date, 23) AS accepted_date,

    -- Parse offer_amount from whatever format it arrived in.
    -- Step 1: strip currency symbols and whitespace
    -- Step 2: handle k suffix (45k = 45000)
    -- Step 3: handle European thousands separator (45.000 = 45000)
    -- Step 4: handle comma thousands separator (45,000 = 45000)
    -- Step 5: cast result to DECIMAL
    TRY_CAST(
        CASE
            -- k suffix: strip k and multiply by 1000
            WHEN LOWER(TRIM(
                    REPLACE(REPLACE(REPLACE(REPLACE(
                    offer_amount,'EUR',''),'€',''),'£',''),' ','')))
                 LIKE '%k'
            THEN CAST(
                    TRY_CAST(
                        LEFT(
                            LOWER(TRIM(
                                REPLACE(REPLACE(REPLACE(REPLACE(
                                offer_amount,'EUR',''),'€',''),'£',''),' ',''))),
                            LEN(LOWER(TRIM(
                                REPLACE(REPLACE(REPLACE(REPLACE(
                                offer_amount,'EUR',''),'€',''),'£',''),' ',''))))-1)
                    AS DECIMAL(12,2)) * 1000
                AS VARCHAR(20))

            -- European decimal: period with exactly 3 digits after it
            WHEN REPLACE(REPLACE(REPLACE(REPLACE(
                    offer_amount,'EUR',''),'€',''),'£',''),' ','')
                 LIKE '[0-9][0-9].[0-9][0-9][0-9]'
              OR REPLACE(REPLACE(REPLACE(REPLACE(
                    offer_amount,'EUR',''),'€',''),'£',''),' ','')
                 LIKE '[0-9][0-9][0-9].[0-9][0-9][0-9]'
            THEN REPLACE(
                    REPLACE(REPLACE(REPLACE(REPLACE(
                    offer_amount,'EUR',''),'€',''),'£',''),' ',''),
                 '.','')

            -- Comma thousands separator
            WHEN REPLACE(REPLACE(REPLACE(REPLACE(
                    offer_amount,'EUR',''),'€',''),'£',''),' ','')
                 LIKE '%,%'
            THEN REPLACE(
                    REPLACE(REPLACE(REPLACE(REPLACE(
                    offer_amount,'EUR',''),'€',''),'£',''),' ',''),
                 ',','')

            -- Already numeric (after stripping symbols)
            ELSE REPLACE(REPLACE(REPLACE(REPLACE(
                    offer_amount,'EUR',''),'€',''),'£',''),' ','')
        END
    AS DECIMAL(12,2)) AS offer_amount,

    offer_currency,

    CAST(
        CASE WHEN LOWER(TRIM(equity_offered)) = 'true' THEN 1 ELSE 0 END
    AS BIT) AS equity_offered,

    offer_status,
    decline_reason

INTO silver.offers
FROM bronze.talentflow_offers
GO


-- =============================================================
-- VALIDATION
-- =============================================================

-- 1. Row count
SELECT 'bronze' AS layer, COUNT(*) AS row_count FROM bronze.talentflow_offers
UNION ALL
SELECT 'silver',           COUNT(*)               FROM silver.offers

-- 2. How many offer_amount values failed to parse
SELECT
    SUM(CASE WHEN offer_amount IS NULL THEN 1 ELSE 0 END) AS null_amounts,
    SUM(CASE WHEN offer_amount IS NOT NULL THEN 1 ELSE 0 END) AS parsed_amounts
FROM silver.offers

-- 3. Amount range check: all values should be plausible salaries
SELECT
    MIN(offer_amount) AS min_amount,
    MAX(offer_amount) AS max_amount,
    AVG(offer_amount) AS avg_amount
FROM silver.offers
WHERE offer_amount IS NOT NULL

-- 4. Offer status distribution
SELECT
    offer_status,
    COUNT(*) AS row_count
FROM silver.offers
GROUP BY offer_status

-- 5. Compare bronze vs silver: how many were non-numeric in bronze
SELECT
    SUM(CASE WHEN TRY_CAST(offer_amount AS DECIMAL(12,2)) IS NULL
             THEN 1 ELSE 0 END) AS non_numeric_in_bronze,
    COUNT(*) AS total
FROM bronze.talentflow_offers