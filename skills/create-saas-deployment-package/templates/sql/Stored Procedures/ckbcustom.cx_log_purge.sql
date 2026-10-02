-- --- ckbcustom.cx_log_purge ---
-- Self-purge for LogWriter: deletes one Source's cx_log rows older than
-- @RetentionDays. Each logger calls it once per process for its own
-- assembly, with the retention from its own config (LogRetentionDays,
-- default 30). Deletes in batches of 5000 so a large backlog never holds a
-- long lock on the shared log. NULL or < 1 days does nothing.
-- Standard object shipped in every SaaS package.
CREATE OR ALTER PROCEDURE ckbcustom.cx_log_purge
    @Source        NVARCHAR(100),
    @RetentionDays INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @Source IS NULL OR @RetentionDays IS NULL OR @RetentionDays < 1
        RETURN;

    DECLARE @cutoff  DATETIME = DATEADD(DAY, -@RetentionDays, GETUTCDATE());
    DECLARE @deleted INT      = 1;

    WHILE @deleted > 0
    BEGIN
        DELETE TOP (5000) FROM ckbcustom.cx_log
        WHERE Source = @Source
          AND dbtime < @cutoff;

        SET @deleted = @@ROWCOUNT;
    END
END
GO

GRANT EXECUTE ON ckbcustom.cx_log_purge TO PUBLIC
GO
