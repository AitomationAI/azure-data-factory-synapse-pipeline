-- Open claims bucketed by age, with outstanding reserve - the adjusters' worklist.
SELECT
    CASE
        WHEN DATEDIFF(day, d.full_date, GETDATE()) <= 30  THEN '0-30 days'
        WHEN DATEDIFF(day, d.full_date, GETDATE()) <= 90  THEN '31-90 days'
        WHEN DATEDIFF(day, d.full_date, GETDATE()) <= 180 THEN '91-180 days'
        ELSE '180+ days'
    END                         AS age_bucket,
    COUNT(*)                    AS open_claims,
    SUM(f.outstanding)          AS outstanding_reserve
FROM dw.fact_claims AS f
JOIN dw.dim_date AS d
    ON d.date_key = f.incident_date_key
WHERE f.is_closed = 0
GROUP BY
    CASE
        WHEN DATEDIFF(day, d.full_date, GETDATE()) <= 30  THEN '0-30 days'
        WHEN DATEDIFF(day, d.full_date, GETDATE()) <= 90  THEN '31-90 days'
        WHEN DATEDIFF(day, d.full_date, GETDATE()) <= 180 THEN '91-180 days'
        ELSE '180+ days'
    END
ORDER BY MIN(DATEDIFF(day, d.full_date, GETDATE()));
