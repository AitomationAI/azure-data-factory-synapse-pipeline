-- Data quality gate. Every check counts violating rows; results are logged,
-- and any failed 'error' check raises so the ADF activity fails and the
-- master pipeline's alert fires.
CREATE PROCEDURE ctl.usp_run_quality_checks
    @run_id VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIME2 = SYSUTCDATETIME();

    INSERT INTO ctl.dq_results (run_id, check_name, severity, failed_rows, passed, checked_at)
    SELECT @run_id, 'fact_duplicate_claims', 'error', COUNT_BIG(*), 0, @now
    FROM (SELECT claim_id FROM dw.fact_claims GROUP BY claim_id HAVING COUNT(*) > 1) AS d;

    INSERT INTO ctl.dq_results (run_id, check_name, severity, failed_rows, passed, checked_at)
    SELECT @run_id, 'fact_paid_exceeds_claimed', 'error', COUNT_BIG(*), 0, @now
    FROM dw.fact_claims WHERE paid_amount > claimed_amount;

    INSERT INTO ctl.dq_results (run_id, check_name, severity, failed_rows, passed, checked_at)
    SELECT @run_id, 'fact_negative_outstanding', 'error', COUNT_BIG(*), 0, @now
    FROM dw.fact_claims WHERE outstanding < 0;

    INSERT INTO ctl.dq_results (run_id, check_name, severity, failed_rows, passed, checked_at)
    SELECT @run_id, 'dim_policyholder_multiple_current', 'error', COUNT_BIG(*), 0, @now
    FROM (SELECT policyholder_id FROM dw.dim_policyholder WHERE is_current = 1
          GROUP BY policyholder_id HAVING COUNT(*) > 1) AS d;

    INSERT INTO ctl.dq_results (run_id, check_name, severity, failed_rows, passed, checked_at)
    SELECT @run_id, 'staged_claims_orphaned', 'warn', COUNT_BIG(*), 0, @now
    FROM stg.claims AS c
    WHERE NOT EXISTS (SELECT 1 FROM dw.dim_policy AS p WHERE p.policy_id = c.policy_id);

    UPDATE ctl.dq_results SET passed = 1 WHERE run_id = @run_id AND failed_rows = 0;

    DECLARE @failures INT = (
        SELECT COUNT(*) FROM ctl.dq_results
        WHERE run_id = @run_id AND severity = 'error' AND passed = 0
    );
    IF @failures > 0
        THROW 50100, 'Data quality gate failed - see ctl.dq_results for this run_id', 1;
END;
GO
