-- One-off calendar seed (2015-2035). Dedicated pools have no recursive CTEs,
-- so a number table is built from a cross join of digits instead.
WITH digits AS (
    SELECT n FROM (VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9)) AS v (n)
),
numbers AS (
    SELECT a.n + 10 * b.n + 100 * c.n + 1000 * d.n AS n
    FROM digits AS a
    CROSS JOIN digits AS b
    CROSS JOIN digits AS c
    CROSS JOIN digits AS d
),
days AS (
    SELECT DATEADD(day, n, CAST('2015-01-01' AS DATE)) AS full_date
    FROM numbers
    WHERE n <= DATEDIFF(day, '2015-01-01', '2035-12-31')
)
INSERT INTO dw.dim_date (date_key, full_date, [year], [quarter], [month], month_name, is_weekend)
SELECT
    CAST(CONVERT(CHAR(8), full_date, 112) AS INT),
    full_date,
    YEAR(full_date),
    DATEPART(quarter, full_date),
    MONTH(full_date),
    DATENAME(month, full_date),
    CASE WHEN DATENAME(weekday, full_date) IN ('Saturday', 'Sunday') THEN 1 ELSE 0 END
FROM days
WHERE NOT EXISTS (SELECT 1 FROM dw.dim_date AS d WHERE d.full_date = days.full_date);
