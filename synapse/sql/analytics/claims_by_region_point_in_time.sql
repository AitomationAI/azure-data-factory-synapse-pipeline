-- Claims by the policyholder's region *at the time of the claim* (SCD2 join),
-- which stays correct even after customers move.
SELECT
    ph.region,
    ph.risk_tier,
    COUNT(*)              AS claims,
    SUM(f.claimed_amount) AS claimed,
    SUM(f.paid_amount)    AS paid,
    AVG(CAST(f.days_to_report AS DECIMAL(8, 2))) AS avg_days_to_report
FROM dw.fact_claims AS f
JOIN dw.dim_policyholder AS ph
    ON ph.policyholder_key = f.policyholder_key
GROUP BY ph.region, ph.risk_tier
ORDER BY claimed DESC;
