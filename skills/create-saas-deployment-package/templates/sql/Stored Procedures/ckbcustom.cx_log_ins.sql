-- --- ckbcustom.cx_log_ins ---
-- Single insert point for LogWriter. Kept trivial on purpose: logging must
-- never be the reason a caller fails, so there is no validation and no
-- RAISERROR here. Standard object shipped in every SaaS package.
CREATE OR ALTER PROCEDURE ckbcustom.cx_log_ins
    @source       NVARCHAR(100),
    @controlName  NVARCHAR(200),
    @username     NVARCHAR(200),
    @level        NVARCHAR(128),
    @message      NVARCHAR(MAX),
    @exception    NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO ckbcustom.cx_log (Source, ControlName, Username, Level, Message, Exception)
    VALUES (@source, @controlName, @username, @level, @message, @exception);
END
GO

GRANT EXECUTE ON ckbcustom.cx_log_ins TO PUBLIC
GO
