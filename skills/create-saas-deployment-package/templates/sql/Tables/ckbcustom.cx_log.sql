-- --- ckbcustom.cx_log ---
-- Application log written by each project's LogWriter (Dapper) through
-- ckbcustom.cx_log_ins. Standard object: every SaaS deployment package
-- carries it, so a project that logs works on a fresh database.
--   Source      = assembly that logged the row (also the purge key)
--   ControlName = the control or class inside that assembly
-- Rerunnable; one batch once GO is stripped (indexes go through EXEC so the
-- batch compiles before the table exists).

IF OBJECT_ID('ckbcustom.cx_log', 'U') IS NULL
BEGIN
    CREATE TABLE ckbcustom.cx_log
    (
        dbkey        INT             NOT NULL IDENTITY(1,1) PRIMARY KEY,
        dbtime       DATETIME        NOT NULL DEFAULT GETUTCDATE(),
        Source       NVARCHAR(100)   NULL,
        ControlName  NVARCHAR(200)   NULL,
        Username     NVARCHAR(200)   NULL,
        Level        NVARCHAR(128)   NULL,
        Message      NVARCHAR(MAX)   NULL,
        Exception    NVARCHAR(MAX)   NULL
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_cx_log_dbtime' AND object_id = OBJECT_ID('ckbcustom.cx_log'))
    EXEC('CREATE NONCLUSTERED INDEX IX_cx_log_dbtime ON ckbcustom.cx_log (dbtime DESC)');

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_cx_log_control_time' AND object_id = OBJECT_ID('ckbcustom.cx_log'))
    EXEC('CREATE NONCLUSTERED INDEX IX_cx_log_control_time ON ckbcustom.cx_log (ControlName, dbtime DESC)');

-- Serves cx_log_purge: each logger trims its own Source.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_cx_log_source_time' AND object_id = OBJECT_ID('ckbcustom.cx_log'))
    EXEC('CREATE NONCLUSTERED INDEX IX_cx_log_source_time ON ckbcustom.cx_log (Source, dbtime)');

EXEC('GRANT SELECT, INSERT, DELETE ON ckbcustom.cx_log TO PUBLIC');
