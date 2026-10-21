-- Truncate-and-load staging from the silver layer for one load date using
-- COPY INTO (fastest ingestion path into a dedicated pool), authenticated
-- with the workspace managed identity - no keys or SAS tokens.
CREATE PROCEDURE stg.usp_stage_from_lake
    @load_date VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;

    IF @load_date NOT LIKE '[12][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]'
        THROW 50001, 'load_date must be formatted yyyy-MM-dd', 1;

    DECLARE @lake VARCHAR(200) = 'https://claimsdevlake.dfs.core.windows.net';
    DECLARE @sql NVARCHAR(4000);

    TRUNCATE TABLE stg.claims;
    TRUNCATE TABLE stg.policies;
    TRUNCATE TABLE stg.policyholders;

    SET @sql = N'COPY INTO stg.claims FROM ''' + @lake + N'/silver/claims/load_date=' + @load_date + N'/*.parquet''
        WITH (FILE_TYPE = ''PARQUET'', CREDENTIAL = (IDENTITY = ''Managed Identity''))';
    EXEC sp_executesql @sql;

    SET @sql = N'COPY INTO stg.policies FROM ''' + @lake + N'/silver/policies/load_date=' + @load_date + N'/*.parquet''
        WITH (FILE_TYPE = ''PARQUET'', CREDENTIAL = (IDENTITY = ''Managed Identity''))';
    EXEC sp_executesql @sql;

    SET @sql = N'COPY INTO stg.policyholders FROM ''' + @lake + N'/silver/policyholders/load_date=' + @load_date + N'/*.parquet''
        WITH (FILE_TYPE = ''PARQUET'', CREDENTIAL = (IDENTITY = ''Managed Identity''))';
    EXEC sp_executesql @sql;
END;
GO
