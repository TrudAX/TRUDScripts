/****** Object:  StoredProcedure [dbo].[AXTopQueryLogMonitor]    Script Date: 5/23/2021 7:09:06 PM ******/
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[AXTopQueryLogMonitor]') AND type in (N'P', N'PC'))
DROP PROCEDURE [dbo].[AXTopQueryLogMonitor]
GO
/****** Object:  StoredProcedure [dbo].[AXTopQueryLogMonitor]    Script Date: 5/23/2021 7:09:06 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
/*
-Version 1.0, Date 2021-05-24
--Create a SQL Agent job with this
EXEC msdb.dbo.[AXTopQueryLogMonitor] @MinPlanTimeMin = 30, @MaxRowToSave = 3, @SendEmailOperator = '', @DaysKeepHistory = 62
EXEC msdb.dbo.AXTopQueryMarkAsApproved @LogId = 30, @ApprovedText = 'That is good'
--Analyse queries
SELECT * FROM [msdb].[dbo].[AXTopQueryLog] order by LogDateTime desc, Id
select * from [msdb].[dbo].[AXTopQueryLog] where id = 250

SELECT [DataBase], [TEXT], query_hash, query_plan_hash, 
(SELECT TOP 1 [query_plan]
     FROM [AXTopQueryLog] AS InnerLog
     WHERE InnerLog.query_plan_hash = [AXTopQueryLog].query_plan_hash AND
		 InnerLog.query_hash = [AXTopQueryLog].query_hash) AS query_plan,
count(*) as NumRec,
AVG([execution_count]) as execution_count,
AVG(total_logical_reads) as total_logical_reads,
[Has 99%],
IsApprovedQuery
FROM [msdb].[dbo].[AXTopQueryLog]
group by [DataBase], [TEXT], query_hash, query_plan_hash, [Has 99%], IsApprovedQuery
*/
-- =============================================
CREATE PROCEDURE [dbo].[AXTopQueryLogMonitor] 

@MinPlanTimeMin INT = 30,
@MaxRowToSave INT = 3,
@SendEmailOperator nvarchar(60) = '',
@DaysKeepHistory INT = 62
AS
BEGIN
	SET NOCOUNT ON;


DECLARE @NewInsertedTbl TABLE (Id INT, [query_plan_hash] binary(8), [query_hash] binary(8))

INSERT INTO dbo.AXTopQueryLog([LogDateTime]
           ,[DataBase]
           ,[TEXT]
           ,[execution_count]
           ,[last_elapsed_time_in_mS]
           ,[total_logical_reads]
           ,[last_logical_reads]
           ,[total_logical_writes]
           ,[last_logical_writes]
           ,[last_physical_reads]
           ,[total_physical_reads]
           ,[total_worker_time_in_S]
           ,[last_worker_time_in_mS]
           ,[total_elapsed_time_in_S]
           ,[last_execution_time]
           ,[Age of the Plan(Minutes)]
           ,[Has 99%]
		   ,[query_plan]
           ,[query_hash]
           ,[query_plan_hash]
		   ,[IsApprovedQuery]) 
OUTPUT INSERTED.Id, INSERTED.query_plan_hash, INSERTED.query_hash INTO @NewInsertedTbl(Id, [query_plan_hash], [query_hash])
SELECT [LogDateTime]
           ,[DataBase]
           ,[TEXT]
           ,[execution_count]
           ,[last_elapsed_time_in_mS]
           ,[total_logical_reads]
           ,[last_logical_reads]
           ,[total_logical_writes]
           ,[last_logical_writes]
           ,[last_physical_reads]
           ,[total_physical_reads]
           ,[total_worker_time_in_S]
           ,[last_worker_time_in_mS]
           ,[total_elapsed_time_in_S]
           ,[last_execution_time]
           ,[Age of the Plan(Minutes)]
           ,[Has 99%]
		   ,[query_plan]
           ,[query_hash]
           ,[query_plan_hash]
		   ,[IsApprovedQuery]
		   FROM (
SELECT TOP (@MaxRowToSave)
 GETDATE() as LogDateTime,
DB_NAME(CONVERT(int, qpa.value)) as [DataBase],
qt.[TEXT],
qs.execution_count,
qs.last_elapsed_time/1000 last_elapsed_time_in_mS,
qs.total_logical_reads, qs.last_logical_reads,
qs.total_logical_writes, qs.last_logical_writes,
qs.last_physical_reads, qs.total_physical_reads,
qs.total_worker_time/1000000 total_worker_time_in_S,
qs.last_worker_time/1000 last_worker_time_in_mS,
qs.total_elapsed_time/1000000 total_elapsed_time_in_S,
qs.last_execution_time,
DATEDIFF(MI,creation_time,GETDATE()) AS [Age of the Plan(Minutes)],
CASE WHEN cast(qp.query_plan  as nvarchar(max)) LIKE N'%<MissingIndexGroup Impact="99%' THEN '!Has 99' ELSE '' END AS [Has 99%] ,
qp.query_plan,
qs.query_hash,
qs.query_plan_hash,
COALESCE((SELECT TOP 1 [IsApprovedQuery]
     FROM [AXTopQueryLogApproved] AS InnerLog
     WHERE InnerLog.query_plan_hash = qs.query_plan_hash AND
		 InnerLog.query_hash = qs.query_hash), 0) AS IsApprovedQuery

FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
CROSS APPLY sys.dm_exec_plan_attributes(qs.plan_handle) qpa
where attribute = 'dbid'
ORDER BY qs.total_logical_reads DESC) A
WHERE A.[Age of the Plan(Minutes)] > @MinPlanTimeMin;

-- DBCC FREEPROCCACHE to reset the counter
--,[IsApprovedQuery]

--DELETE FETCH Cursor
DELETE @NewInsertedTbl
	where query_plan_hash = 0x0000000000000000;

--UPDATE prev records
UPDATE AXTopQueryLogApproved
	SET LogDateTime = GETDATE() 
FROM AXTopQueryLogApproved c
    INNER JOIN @NewInsertedTbl t
        ON c.query_plan_hash = t.query_plan_hash AND c.query_hash = t.query_hash; 

--DELETE prev records

DELETE FROM o1
from   @NewInsertedTbl as o1
WHERE EXISTS (SELECT * FROM AXTopQueryLogApproved la
              WHERE la.query_plan_hash = o1.query_plan_hash
                AND la.query_hash      = o1.query_hash);

DECLARE @NumOfRec INT
SELECT @NumOfRec = count(*) FROM @NewInsertedTbl

IF @SendEmailOperator <> '' AND @NumOfRec > 0
BEGIN
        DECLARE @Msg NVARCHAR(max)
        DECLARE @HTMLStr NVARCHAR(max)

        SET @Msg = N'AX new TOP query Alert';

        DECLARE @oper_email NVARCHAR(100)
        SET @oper_email = (SELECT email_address from msdb.dbo.sysoperators WHERE name = @SendEmailOperator)

        DECLARE @body NVARCHAR(MAX)
        SET     @body = N'<table>'
            + N'<tr><th>ID</th><th>Database</th><th>Execution count</th><th>TEXT</th></tr>'
            + CAST((
                SELECT l.Id AS td, 
					   l.[DataBase]  AS td,
					   l.execution_count AS td,
					   l.[TEXT]  AS td
				FROM AXTopQueryLog l
				INNER JOIN @NewInsertedTbl t  ON t.Id = l.Id
                    FOR XML RAW('tr'), ELEMENTS
            ) AS NVARCHAR(MAX))
            + N'</table>'

        SET @body = REPLACE(@body, '<tdc>', '<td class="center">');
        SET @body = REPLACE(@body, '</tdc>', '</td>');

		--get CPU usage history
		DECLARE @ts_now bigint = (SELECT cpu_ticks/(cpu_ticks/ms_ticks)FROM sys.dm_os_sys_info); 

        DECLARE @body2 NVARCHAR(MAX)
        SET     @body2 = N'<table>'
            + N'<tr><th>SQL Server CPU Utilization</th><th>System Idle</th><th>Other Process CPU</th><th>Event Time</th></tr>'
            + CAST((
			SELECT TOP(20) SQLProcessUtilization AS td, 
               SystemIdle AS td, 
               100 - SystemIdle - SQLProcessUtilization AS td, 
               DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) AS td
			FROM ( 
				  SELECT record.value('(./Record/@id)[1]', 'int') AS record_id, 
						record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') 
						AS [SystemIdle], 
						record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 
						'int') 
						AS [SQLProcessUtilization], [timestamp] 
				  FROM ( 
						SELECT [timestamp], CONVERT(xml, record) AS [record] 
						FROM sys.dm_os_ring_buffers 
						WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR' 
						AND record LIKE '%<SystemHealth>%') AS x 
				  ) AS y 
			ORDER BY record_id DESC
                    FOR XML RAW('tr'), ELEMENTS
            ) AS NVARCHAR(MAX))
            + N'</table>'

        SET @body2 = REPLACE(@body2, '<tdc>', '<td class="center">');
        SET @body2 = REPLACE(@body2, '</tdc>', '</td>');


        SET @HTMLStr = N'<html><body>' + @Msg + N'<br><br>' + @body  + N'<br><b>CPU Usage</b><br>' + @body2 + N'</body></html>';


        --SELECT @HTMLStr  --DEBUG
        --SET @oper_email = 'trud81@gmail.com'  --DEBUG

        EXEC msdb.dbo.sp_send_dbmail  @recipients = @oper_email, @subject = @Msg,  @body = @HTMLStr,  @body_format = 'HTML' ;
END;

--INSERT new records
INSERT INTO [dbo].[AXTopQueryLogApproved]
           ([LogDateTime]
           ,[DataBase]
           ,[TEXT]
           ,[query_hash]
           ,[query_plan_hash]
           )
SELECT GETDATE(), 
	   l.[DataBase],
	   l.[TEXT],
	   l.query_hash,
	   l.query_plan_hash
FROM AXTopQueryLog l
INNER JOIN @NewInsertedTbl t  ON t.Id = l.Id;

IF @DaysKeepHistory > 0
BEGIN
	DECLARE @TruncDate datetime
	SET @TruncDate = DATEADD(day, -1 * @DaysKeepHistory, GETDATE())

	DELETE AXTopQueryLog
		WHERE LogDateTime < @TruncDate;
	
	DELETE AXTopQueryLogApproved
		WHERE LogDateTime < @TruncDate AND IsApprovedQuery = 0;
END;



END
GO
