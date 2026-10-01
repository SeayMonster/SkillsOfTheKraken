-- ============================================================
-- ckbcustom.cx_deploy_log
--
-- One row per deploy or rollback run by Deploy-SQL.ps1 or
-- Rollback.ps1 -- the record of what a database is running:
--   SELECT TOP 5 * FROM ckbcustom.cx_deploy_log ORDER BY dbkey DESC
--
-- Deploy-SQL.ps1 runs this itself, before anything else, so the
-- log exists before its first row is written. One batch, no GO
-- (it is executed through ADO.NET). Rerunnable.
-- ============================================================
IF OBJECT_ID('ckbcustom.cx_deploy_log', 'U') IS NULL
BEGIN
    CREATE TABLE ckbcustom.cx_deploy_log (
        dbkey         INT            NOT NULL IDENTITY(1,1) PRIMARY KEY,
        dbtime        DATETIME       NOT NULL DEFAULT GETUTCDATE(),
        Release       VARCHAR(20)    NOT NULL,
        Build         INT            NOT NULL,
        Tag           VARCHAR(100)   NULL,
        CommitSha     VARCHAR(40)    NULL,
        Action        VARCHAR(20)    NOT NULL,
        Result        VARCHAR(20)    NOT NULL,
        Host          NVARCHAR(128)  NOT NULL,
        RunBy         NVARCHAR(128)  NOT NULL,
        StartedAt     DATETIME       NOT NULL,
        FinishedAt    DATETIME       NULL,
        FileCount     INT            NULL,
        BackupFolder  NVARCHAR(400)  NULL,
        Objects       NVARCHAR(MAX)  NULL,
        RolledBackKey INT            NULL,
        Message       NVARCHAR(MAX)  NULL
    );
    EXEC('GRANT SELECT, INSERT, UPDATE ON ckbcustom.cx_deploy_log TO PUBLIC');
END
