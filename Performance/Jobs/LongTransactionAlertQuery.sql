DECLARE @ThresholdTimeMin INT = 60
DECLARE @NumOfLocks INT
DECLARE @LocksTime INT

SELECT @NumOfLocks = COUNT(*), @LocksTime = MAX(DATEDIFF(mi,a.database_transaction_begin_time, SYSDATETIME())) FROM  sys.dm_tran_database_transactions a   
  where a.database_transaction_begin_time is not NULL AND
	DATEDIFF(mi,a.database_transaction_begin_time, SYSDATETIME()) >= @ThresholdTimeMin
	AND CAST(Db_name(a.database_id) AS VARCHAR(30)) <> 'msdb'

IF @NumOfLocks > 0 
    BEGIN
        DECLARE @Msg NVARCHAR(max)
        DECLARE @HTMLStr NVARCHAR(max)

        SET @Msg = N'AX long transaction alert!'
            + N' Transaction duration:'
            + CAST(@LocksTime AS NVARCHAR(10))
            + N' min';

        DECLARE @oper_email NVARCHAR(100)
        SET @oper_email = (SELECT email_address from msdb.dbo.sysoperators WHERE name = N'AXAlert')

        DECLARE @body NVARCHAR(MAX)
        SET     @body = N'<table>'
            + N'<tr><th>Session ID</th><th>AXUser</th><th>Database Name</th><th>transaction_begin_time</th><th>DurationMin</th><th>MB used</th><th>Record count</th><th>login_time</th><th>host_name</th><th>program_name</th></tr>'
            + CAST((
                SELECT b.session_id AS td,
		  cast(curSessions.context_info as varchar(128)) AS td,
       CAST(Db_name(a.database_id) AS VARCHAR(30)) AS td,  
       a.database_transaction_begin_time AS td,
	   DATEDIFF(mi,a.database_transaction_begin_time, SYSDATETIME()) AS td,
       a.database_transaction_log_bytes_used / 1024.0 / 1024.0 AS td,      
       a.database_transaction_log_record_count  AS td,
	   curSessions.login_time AS td,
	   curSessions.host_name AS td,
	   curSessions.program_name AS td
FROM   sys.dm_tran_database_transactions a
       JOIN sys.dm_tran_session_transactions b
         ON a.transaction_id = b.transaction_id
		  JOIN sys.dm_exec_sessions curSessions
	      ON curSessions.session_id = b.session_id
		  where a.database_transaction_begin_time is not NULL
                    FOR XML RAW('tr'), ELEMENTS
            ) AS NVARCHAR(MAX))
            + N'</table>'

        SET @body = REPLACE(@body, '<tdc>', '<td class="center">')
        SET @body = REPLACE(@body, '</tdc>', '</td>')

        SET @HTMLStr = N'<html><body>' + @Msg + N'<br><br>' + @body + N'</body></html>';

        --SELECT @HTMLStr  --DEBUG
        --SET @oper_email = 'trud81@gmail.com'  --DEBUG

        EXEC msdb.dbo.sp_send_dbmail
            @recipients = @oper_email,
            @subject = @Msg,
            @body = @HTMLStr,
            @body_format = 'HTML' ;
		
        --RAISERROR (911421,10,1,@msg) WITH LOG;
    END

/*orig query
		 SELECT b.session_id AS [Session ID],
		  cast(curSessions.context_info as varchar(128)) as AXUser,
       CAST(Db_name(a.database_id) AS VARCHAR(20)) AS [Database Name],  
       a.database_transaction_begin_time,
	   DATEDIFF(mi,a.database_transaction_begin_time, SYSDATETIME()) as DurationMin,
       a.database_transaction_log_bytes_used / 1024.0 / 1024.0 AS [MB used],      
       a.database_transaction_log_record_count AS [Record count],
	   curSessions.login_time,
	   curSessions.host_name,
	   curSessions.program_name
FROM   sys.dm_tran_database_transactions a
       JOIN sys.dm_tran_session_transactions b
         ON a.transaction_id = b.transaction_id
		  JOIN sys.dm_exec_sessions curSessions
	      ON curSessions.session_id = b.session_id
		  where a.database_transaction_begin_time is not NULL
      
*/