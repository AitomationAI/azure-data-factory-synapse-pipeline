-- SCD Type 1: overwrite changed policies, insert new ones.
-- Dedicated pools do not support ANSI joins in UPDATE, hence the implicit join.
CREATE PROCEDURE dw.usp_load_dim_policy
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dw.dim_policy
    SET policyholder_id = s.policyholder_id,
        product_line    = s.product_line,
        coverage_limit  = s.coverage_limit,
        annual_premium  = s.annual_premium,
        start_date      = s.start_date,
        end_date        = s.end_date,
        channel         = s.channel,
        updated_at      = SYSUTCDATETIME()
    FROM stg.policies AS s
    WHERE dw.dim_policy.policy_id = s.policy_id;

    INSERT INTO dw.dim_policy
        (policy_id, policyholder_id, product_line, coverage_limit, annual_premium,
         start_date, end_date, channel, updated_at)
    SELECT s.policy_id, s.policyholder_id, s.product_line, s.coverage_limit, s.annual_premium,
           s.start_date, s.end_date, s.channel, SYSUTCDATETIME()
    FROM stg.policies AS s
    WHERE NOT EXISTS (SELECT 1 FROM dw.dim_policy AS d WHERE d.policy_id = s.policy_id);
END;
GO
