-- =============================================================================
-- Staging (heap, round-robin = fastest load) and the dw star schema.
-- Distribution choices:
--   small dimensions -> REPLICATE (no data movement on joins)
--   fact_claims      -> HASH(policy_id) + clustered columnstore
-- =============================================================================

CREATE TABLE stg.claims
(
    claim_id        VARCHAR(20)    NOT NULL,
    policy_id       VARCHAR(20)    NOT NULL,
    claim_type      VARCHAR(50)    NULL,
    incident_date   DATE           NOT NULL,
    reported_date   DATE           NULL,
    claim_status    VARCHAR(20)    NOT NULL,
    claimed_amount  DECIMAL(14, 2) NOT NULL,
    paid_amount     DECIMAL(14, 2) NOT NULL,
    adjuster_id     VARCHAR(20)    NULL,
    modified_at     DATETIME2      NOT NULL,
    days_to_report  INT            NULL,
    load_date       DATE           NOT NULL
)
WITH (DISTRIBUTION = ROUND_ROBIN, HEAP);
GO

CREATE TABLE stg.policies
(
    policy_id        VARCHAR(20)    NOT NULL,
    policyholder_id  VARCHAR(20)    NOT NULL,
    product_line     VARCHAR(50)    NOT NULL,
    coverage_limit   DECIMAL(14, 2) NULL,
    annual_premium   DECIMAL(12, 2) NULL,
    start_date       DATE           NULL,
    end_date         DATE           NULL,
    channel          VARCHAR(30)    NULL
)
WITH (DISTRIBUTION = ROUND_ROBIN, HEAP);
GO

CREATE TABLE stg.policyholders
(
    policyholder_id  VARCHAR(20)    NOT NULL,
    full_name        VARCHAR(200)   NULL,
    birth_year       INT            NULL,
    region           VARCHAR(50)    NULL,
    risk_tier        VARCHAR(10)    NULL,
    row_hash         CHAR(64)       NOT NULL
)
WITH (DISTRIBUTION = ROUND_ROBIN, HEAP);
GO

CREATE TABLE dw.dim_date
(
    date_key      INT          NOT NULL,
    full_date     DATE         NOT NULL,
    [year]        SMALLINT     NOT NULL,
    [quarter]     TINYINT      NOT NULL,
    [month]       TINYINT      NOT NULL,
    month_name    VARCHAR(10)  NOT NULL,
    is_weekend    BIT          NOT NULL
)
WITH (DISTRIBUTION = REPLICATE, CLUSTERED INDEX (date_key));
GO

CREATE TABLE dw.dim_policy
(
    policy_key       INT IDENTITY(1, 1) NOT NULL,
    policy_id        VARCHAR(20)    NOT NULL,
    policyholder_id  VARCHAR(20)    NOT NULL,
    product_line     VARCHAR(50)    NOT NULL,
    coverage_limit   DECIMAL(14, 2) NULL,
    annual_premium   DECIMAL(12, 2) NULL,
    start_date       DATE           NULL,
    end_date         DATE           NULL,
    channel          VARCHAR(30)    NULL,
    updated_at       DATETIME2      NOT NULL
)
WITH (DISTRIBUTION = REPLICATE, CLUSTERED COLUMNSTORE INDEX);
GO

-- SCD Type 2: region / risk tier changes keep history for point-in-time reporting.
CREATE TABLE dw.dim_policyholder
(
    policyholder_key INT IDENTITY(1, 1) NOT NULL,
    policyholder_id  VARCHAR(20)    NOT NULL,
    full_name        VARCHAR(200)   NULL,
    birth_year       INT            NULL,
    region           VARCHAR(50)    NULL,
    risk_tier        VARCHAR(10)    NULL,
    row_hash         CHAR(64)       NOT NULL,
    valid_from       DATETIME2      NOT NULL,
    valid_to         DATETIME2      NULL,
    is_current       BIT            NOT NULL
)
WITH (DISTRIBUTION = REPLICATE, CLUSTERED COLUMNSTORE INDEX);
GO

CREATE TABLE dw.fact_claims
(
    claim_id          VARCHAR(20)    NOT NULL,
    policy_id         VARCHAR(20)    NOT NULL,
    policy_key        INT            NOT NULL,
    policyholder_key  INT            NOT NULL,
    incident_date_key INT            NOT NULL,
    reported_date_key INT            NULL,
    claim_type        VARCHAR(50)    NULL,
    claim_status      VARCHAR(20)    NOT NULL,
    claimed_amount    DECIMAL(14, 2) NOT NULL,
    paid_amount       DECIMAL(14, 2) NOT NULL,
    outstanding       DECIMAL(14, 2) NOT NULL,
    days_to_report    INT            NULL,
    is_closed         BIT            NOT NULL,
    source_modified_at DATETIME2     NOT NULL,
    run_id            VARCHAR(50)    NOT NULL,
    loaded_at         DATETIME2      NOT NULL
)
WITH (DISTRIBUTION = HASH(policy_id), CLUSTERED COLUMNSTORE INDEX);
GO
