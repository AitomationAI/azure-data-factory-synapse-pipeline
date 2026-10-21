-- SCD Type 2 for policyholders, wrapped in a transaction so the dimension
-- is never left with an expired row but no replacement.
CREATE PROCEDURE dw.usp_load_dim_policyholder
    @run_id VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIME2 = SYSUTCDATETIME();
    DECLARE @expired BIGINT, @inserted BIGINT;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. close the current version of changed policyholders
        UPDATE dw.dim_policyholder
        SET valid_to = @now,
            is_current = 0
        FROM stg.policyholders AS s
        WHERE dw.dim_policyholder.policyholder_id = s.policyholder_id
          AND dw.dim_policyholder.is_current = 1
          AND dw.dim_policyholder.row_hash <> s.row_hash;
        SET @expired = @@ROWCOUNT;

        -- 2. open a new current version for new + changed policyholders
        INSERT INTO dw.dim_policyholder
            (policyholder_id, full_name, birth_year, region, risk_tier, row_hash, valid_from, valid_to, is_current)
        SELECT s.policyholder_id, s.full_name, s.birth_year, s.region, s.risk_tier, s.row_hash, @now, NULL, 1
        FROM stg.policyholders AS s
        WHERE NOT EXISTS (
            SELECT 1 FROM dw.dim_policyholder AS d
            WHERE d.policyholder_id = s.policyholder_id AND d.is_current = 1
        );
        SET @inserted = @@ROWCOUNT;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    INSERT INTO ctl.load_log (run_id, step_name, rows_affected, logged_at)
    VALUES (@run_id, 'dim_policyholder:expired', @expired, @now);
    INSERT INTO ctl.load_log (run_id, step_name, rows_affected, logged_at)
    VALUES (@run_id, 'dim_policyholder:inserted', @inserted, @now);
END;
GO
