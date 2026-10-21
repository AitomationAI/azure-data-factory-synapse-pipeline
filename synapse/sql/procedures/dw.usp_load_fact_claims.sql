-- Upsert claims with MERGE (supported on HASH-distributed targets).
-- New claims bind to the *current* policyholder version; updates to an
-- existing claim keep their original dimension keys (point-in-time history).
CREATE PROCEDURE dw.usp_load_fact_claims
    @run_id VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIME2 = SYSUTCDATETIME();

    -- Resolve surrogate keys once; CTAS is the fastest way to build it.
    IF OBJECT_ID('tempdb..#claims_keyed') IS NOT NULL DROP TABLE #claims_keyed;

    CREATE TABLE #claims_keyed
    WITH (DISTRIBUTION = HASH(policy_id), HEAP)
    AS
    SELECT
        c.claim_id,
        c.policy_id,
        p.policy_key,
        ph.policyholder_key,
        CAST(CONVERT(CHAR(8), c.incident_date, 112) AS INT) AS incident_date_key,
        CAST(CONVERT(CHAR(8), c.reported_date, 112) AS INT) AS reported_date_key,
        c.claim_type,
        c.claim_status,
        c.claimed_amount,
        c.paid_amount,
        CASE WHEN c.claim_status IN ('paid', 'denied', 'closed') THEN 0
             ELSE c.claimed_amount - c.paid_amount END AS outstanding,
        c.days_to_report,
        CASE WHEN c.claim_status IN ('paid', 'denied', 'closed') THEN 1 ELSE 0 END AS is_closed,
        c.modified_at
    FROM stg.claims AS c
    JOIN dw.dim_policy AS p
        ON p.policy_id = c.policy_id
    JOIN dw.dim_policyholder AS ph
        ON ph.policyholder_id = p.policyholder_id AND ph.is_current = 1;

    MERGE INTO dw.fact_claims AS t
    USING #claims_keyed AS s
        ON t.claim_id = s.claim_id AND t.policy_id = s.policy_id
    WHEN MATCHED AND s.modified_at > t.source_modified_at THEN UPDATE SET
        t.claim_status       = s.claim_status,
        t.claimed_amount     = s.claimed_amount,
        t.paid_amount        = s.paid_amount,
        t.outstanding        = s.outstanding,
        t.is_closed          = s.is_closed,
        t.reported_date_key  = s.reported_date_key,
        t.source_modified_at = s.modified_at,
        t.run_id             = @run_id,
        t.loaded_at          = @now
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (claim_id, policy_id, policy_key, policyholder_key, incident_date_key, reported_date_key,
         claim_type, claim_status, claimed_amount, paid_amount, outstanding, days_to_report,
         is_closed, source_modified_at, run_id, loaded_at)
    VALUES
        (s.claim_id, s.policy_id, s.policy_key, s.policyholder_key, s.incident_date_key, s.reported_date_key,
         s.claim_type, s.claim_status, s.claimed_amount, s.paid_amount, s.outstanding, s.days_to_report,
         s.is_closed, s.modified_at, @run_id, @now);

    INSERT INTO ctl.load_log (run_id, step_name, rows_affected, logged_at)
    SELECT @run_id, 'fact_claims:staged', COUNT_BIG(*), @now FROM #claims_keyed;

    -- Claims whose policy is unknown never reach the fact table - surface them.
    INSERT INTO ctl.load_log (run_id, step_name, rows_affected, logged_at)
    SELECT @run_id, 'fact_claims:orphaned', COUNT_BIG(*), @now
    FROM stg.claims AS c
    WHERE NOT EXISTS (SELECT 1 FROM #claims_keyed AS k WHERE k.claim_id = c.claim_id);

    DROP TABLE #claims_keyed;
END;
GO
