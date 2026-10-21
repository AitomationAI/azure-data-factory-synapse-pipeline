-- Loss ratio (paid claims / premium) by product line - the headline KPI.
-- Claims are aggregated per policy first so premium is never double counted.
WITH claims_per_policy AS (
    SELECT policy_key, COUNT(*) AS claims, SUM(paid_amount) AS paid
    FROM dw.fact_claims
    GROUP BY policy_key
)
SELECT
    p.product_line,
    COUNT(*)                                       AS policies,
    SUM(COALESCE(c.claims, 0))                     AS claims,
    SUM(p.annual_premium)                          AS annual_premium,
    SUM(COALESCE(c.paid, 0))                       AS paid_claims,
    CAST(100.0 * SUM(COALESCE(c.paid, 0)) / NULLIF(SUM(p.annual_premium), 0) AS DECIMAL(6, 1)) AS loss_ratio_pct
FROM dw.dim_policy AS p
LEFT JOIN claims_per_policy AS c
    ON c.policy_key = p.policy_key
GROUP BY p.product_line
ORDER BY loss_ratio_pct DESC;
