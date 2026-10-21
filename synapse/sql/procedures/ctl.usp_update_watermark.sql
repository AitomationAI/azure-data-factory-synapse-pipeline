-- Called by ADF after each successful incremental copy.
CREATE PROCEDURE ctl.usp_update_watermark
    @source_name   VARCHAR(50),
    @new_watermark VARCHAR(30),
    @rows_copied   BIGINT,
    @run_id        VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE ctl.source_tables
    SET watermark_value  = @new_watermark,
        last_run_id      = @run_id,
        last_rows_copied = @rows_copied,
        last_loaded_at   = SYSUTCDATETIME()
    WHERE source_name = @source_name;

    INSERT INTO ctl.load_log (run_id, step_name, rows_affected, logged_at)
    VALUES (@run_id, CONCAT('extract:', @source_name), @rows_copied, SYSUTCDATETIME());
END;
GO
