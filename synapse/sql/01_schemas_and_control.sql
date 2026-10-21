-- =============================================================================
-- Synapse dedicated SQL pool: schemas + control tables
--   ctl  pipeline metadata (what to extract, watermarks, run + DQ logs)
--   stg  per-run staging, loaded with COPY INTO from silver Parquet
--   dw   star schema served to Power BI
-- =============================================================================

CREATE SCHEMA ctl;
GO
CREATE SCHEMA stg;
GO
CREATE SCHEMA dw;
GO

-- Drives pl_ingest_sql_incremental: add a row here to onboard a new table.
CREATE TABLE ctl.source_tables
(
    source_name       VARCHAR(50)   NOT NULL,
    source_schema     VARCHAR(50)   NOT NULL,
    source_table      VARCHAR(100)  NOT NULL,
    watermark_column  VARCHAR(100)  NOT NULL,
    watermark_value   VARCHAR(30)   NOT NULL,
    is_active         BIT           NOT NULL,
    last_run_id       VARCHAR(50)   NULL,
    last_rows_copied  BIGINT        NULL,
    last_loaded_at    DATETIME2     NULL
)
WITH (DISTRIBUTION = REPLICATE, CLUSTERED INDEX (source_name));
GO

INSERT INTO ctl.source_tables (source_name, source_schema, source_table, watermark_column, watermark_value, is_active)
VALUES ('claims', 'dbo', 'Claims', 'ModifiedAt', '1900-01-01T00:00:00', 1);
INSERT INTO ctl.source_tables (source_name, source_schema, source_table, watermark_column, watermark_value, is_active)
VALUES ('policies', 'dbo', 'Policies', 'ModifiedAt', '1900-01-01T00:00:00', 1);
GO

CREATE TABLE ctl.load_log
(
    run_id        VARCHAR(50)   NOT NULL,
    step_name     VARCHAR(100)  NOT NULL,
    rows_affected BIGINT        NULL,
    logged_at     DATETIME2     NOT NULL
)
WITH (DISTRIBUTION = ROUND_ROBIN, HEAP);
GO

CREATE TABLE ctl.dq_results
(
    run_id         VARCHAR(50)   NOT NULL,
    check_name     VARCHAR(100)  NOT NULL,
    severity       VARCHAR(10)   NOT NULL,
    failed_rows    BIGINT        NOT NULL,
    passed         BIT           NOT NULL,
    checked_at     DATETIME2     NOT NULL
)
WITH (DISTRIBUTION = ROUND_ROBIN, HEAP);
GO
