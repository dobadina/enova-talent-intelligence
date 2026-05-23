-- =============================================================
-- STORED PROCEDURE: pipeline.run
-- Calls silver.load_all then gold.load_all in sequence.
-- Logs the result to pipeline.run_log with timing,
-- row counts, and error messages if anything fails.
-- =============================================================

CREATE OR ALTER PROCEDURE pipeline.run
    @triggered_by VARCHAR(100) = 'manual'
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @run_start      DATETIME = GETDATE()
    DECLARE @run_end        DATETIME
    DECLARE @status         VARCHAR(20)
    DECLARE @error_message  NVARCHAR(MAX)
    DECLARE @rows_silver    INT
    DECLARE @rows_gold      INT

    BEGIN TRY

        -- Silver load
        EXEC silver.load_all

        SELECT @rows_silver =
            (SELECT COUNT(*) FROM silver.jobs) +
            (SELECT COUNT(*) FROM silver.candidates) +
            (SELECT COUNT(*) FROM silver.applications) +
            (SELECT COUNT(*) FROM silver.pipeline_events) +
            (SELECT COUNT(*) FROM silver.offers) +
            (SELECT COUNT(*) FROM silver.employees) +
            (SELECT COUNT(*) FROM silver.performance) +
            (SELECT COUNT(*) FROM silver.compensation) +
            (SELECT COUNT(*) FROM silver.headcount_plan)

        -- Gold load
        EXEC gold.load_all

        SELECT @rows_gold =
            (SELECT COUNT(*) FROM gold.fact_applications) +
            (SELECT COUNT(*) FROM gold.fact_pipeline_events) +
            (SELECT COUNT(*) FROM gold.fact_offers) +
            (SELECT COUNT(*) FROM gold.fact_headcount) +
            (SELECT COUNT(*) FROM gold.dim_job) +
            (SELECT COUNT(*) FROM gold.dim_candidate)

        SET @status = 'SUCCESS'

    END TRY
    BEGIN CATCH

        SET @status        = 'FAILED'
        SET @error_message = ERROR_MESSAGE()

    END CATCH

    -- Log the result regardless of success or failure
    SET @run_end = GETDATE()

    INSERT INTO pipeline.run_log (
        run_start, run_end, status,
        rows_silver, rows_gold,
        error_message, triggered_by
    )
    VALUES (
        @run_start, @run_end, @status,
        @rows_silver, @rows_gold,
        @error_message, @triggered_by
    )

    -- Return the log entry
    SELECT
        log_id,
        run_start,
        run_end,
        DATEDIFF(SECOND, run_start, run_end)    AS duration_seconds,
        status,
        rows_silver,
        rows_gold,
        error_message,
        triggered_by
    FROM pipeline.run_log
    WHERE log_id = SCOPE_IDENTITY()

END
GO

-- Test it
EXEC pipeline.run @triggered_by = 'manual_test'