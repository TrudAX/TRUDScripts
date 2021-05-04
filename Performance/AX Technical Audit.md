**Technical audit scripts**

- [Get information about the system](#get-information-about-the-system)
  - [Database size](#database-size)
  - [System statistics](#system-statistics)
  - [SQL Agent jobs](#sql-agent-jobs)
  - [Table statistics](#table-statistics)
  - [sp_Blitz](#sp_blitz)
- [Review database status](#review-database-status)
  - [Index defragmentation](#index-defragmentation)
  - [Missing indexes](#missing-indexes)
  - [Unused indexes](#unused-indexes)
  - [Disk I / o](#disk-i--o)
  - [Wait statistics](#wait-statistics)
- [Database monitoring](#database-monitoring)
  - [Database locks](#database-locks)
  - [Cursors for the session](#cursors-for-the-session)
  - [Show SQL query for the AX user](#show-sql-query-for-the-ax-user)
  - [Show current trance flags](#show-current-trance-flags)
  - [Clear SQL server cache](#clear-sql-server-cache)
  - [Clear AX cache](#clear-ax-cache)
  - [Longest transactions](#longest-transactions)
  - [Get Top SQL](#get-top-sql)
- [Database changes](#database-changes)
  - [Create a plan guide](#create-a-plan-guide)
  - [Delete a plan from the cache](#delete-a-plan-from-the-cache)
  - [Find disabled tables](#find-disabled-tables)
  - [Index maintenance](#index-maintenance)
- [Helper AX jobs](#helper-ax-jobs)
  - [Enabling tracing](#enabling-tracing)
  - [Delete similar traces](#delete-similar-traces)
  - [SysdatabaseLog size](#sysdatabaselog-size)
  - [Number sequences check](#number-sequences-check)
  - [Check the entire table cache](#check-the-entire-table-cache)
- [Performance hints](#performance-hints)
  - [CPUID](#cpuid)
  - [Delete from a large table](#delete-from-a-large-table)
  - [Blocking alert](#blocking-alert)
  - [Blocking in AX](#blocking-in-ax)
  - [Auto sorting for a view-based forms](#auto-sorting-for-a-view-based-forms)

# Get information about the system

## Database size

```sql
CREATE TABLE #Results(
  [Name] nvarchar(128),
  [Rows] char(11),
  ReservedKB varchar(18),
  DataKB varchar(18),
  Index_sizeKB varchar(18),
  UnusedKB varchar(18))
GO
INSERT INTO #Results
exec sp_msforeachtable @command1 = N'exec sp_spaceused ''?'', false'

SELECT [Name], [rows], REPLACE(ReservedKB, ' KB', '') as ReservedKB, REPLACE(DataKB, ' KB', '') as DataKB,
    REPLACE(Index_sizeKB, ' KB', '') as Index_sizeKB, REPLACE(UnusedKB, ' KB', '') as UnusedKB FROM #Results
ORDER BY [NAME]
GO

DROP TABLE #Results
GO

--for Azure SQL

select o.name, max(s.row_count) AS 'Rows',
    sum(s.reserved_page_count) * 8.0 / (1024 * 1024) as 'GB',
    (8 * 1024 * sum(s.reserved_page_count)) / (max(s.row_count)) as 'Bytes/Row'
from sys.dm_db_partition_stats s, sys.objects o
where o.object_id = s.object_id
group by o.name
having max(s.row_count) > 0
order by GB desc
```

## System statistics

- Version of AX and SQL
- How much memory is left on SQL Server
- Batch jobs and their time of execution
- Pending WF status
- Number of Financial dimension sets

```sql
select name, is_read_committed_snapshot_on  from sys.databases
alter database Dynamics set read_committed_snapshot on
```

```sql
DECLARE  @m int
set @m = DATEDIFF(mi,SYSUTCDATETIME(), SYSDATETIME())

SELECT [STATUS]
      ,[FINISHING]
      ,[CAPTION]
      ,[BATCHJOBID]
      ,DATEADD(minute, @m, [STARTDATETIME]) as [STARTDATETIME]
      ,DATEADD(minute, @m, [ENDDATETIME]) as [ENDDATETIME]
      ,DATEDIFF(mi, STARTDATETIME, enddatetime) as [DurationMi]
      ,[COMPANY]
      ,[ALERTSPROCESSED]
      ,[BATCHCREATEDBY]
      ,[CANCELEDBY]
  FROM [dbo].[BATCHJOBHISTORY]
where DATEDIFF(mi, STARTDATETIME, enddatetime) > 30 and STARTDATETIME > CONVERT(datetime, '2019-08-01', 120)
--order by STARTDATETIME desc
order by CAPTION desc

--Active users by hour
DECLARE  @mOffset int
set @mOffset = DATEDIFF(mi,SYSUTCDATETIME(), SYSDATETIME())

SET DATEFORMAT YMD
DECLARE @hrs TABLE (HH INT NOT NULL)
DECLARE @DateFrom date = '2019-08-08', @DateTo date = CONVERT(datetime, '2019-08-08', 120)

INSERT INTO @hrs
SELECT TOP 24 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) FROM sys.objects

SELECT HH AS Hour
    ,avg(UserCnt) AS [Avg users]
    ,max(UserCnt) AS [Max users]
FROM (
    SELECT DATE
        ,HH
        ,count(*) AS UserCnt
    FROM (
        SELECT DISTINCT USERID, CAST(DATEADD(mi, @mOffset, CREATEDDATETIME) AS DATE) AS DATE
            ,HH
        FROM SYSUSERLOG
        CROSS JOIN @hrs
        WHERE CAST(DATEADD(mi, @mOffset, CREATEDDATETIME) AS DATE) = CAST(DATEADD(mi, @mOffset, LOGOUTDATETIME) AS DATE)
            AND DATEPART(hour, DATEADD(mi, @mOffset, CREATEDDATETIME)) <= HH
            AND DATEPART(hour, DATEADD(mi, @mOffset, LOGOUTDATETIME)) >= HH
            AND CLIENTTYPE = 1
        ) T
    WHERE DATE BETWEEN @DateFrom AND @DateTo
    GROUP BY DATE
        ,HH
    ) TT
GROUP BY HH
ORDER BY HH
```

## SQL Agent jobs

```sql
SELECT [sJOB].[name] AS [JobName]
    ,CASE [sJOBH].[run_status] WHEN 0 THEN 'Failed' WHEN 1 THEN 'Succeeded' WHEN 2 THEN 'Retry' WHEN 3 THEN 'Canceled' WHEN 4 THEN 'Running' -- In Progress
        END AS [LastRunStatus]
    ,STUFF(STUFF(RIGHT('000000' + CAST([sJOBH].[run_duration] AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':') AS [LastRunDuration (HH:MM:SS)]
    ,CASE WHEN [sJOBH].[run_date] IS NULL
        OR [sJOBH].[run_time] IS NULL THEN NULL ELSE CAST(CAST([sJOBH].[run_date] AS CHAR(8)) + ' ' + STUFF(STUFF(RIGHT('000000' + CAST([sJOBH].[run_time] AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':') AS DATETIME) END AS [LastRunDateTime]
    ,[sJOBH].[message] AS [LastRunStatusMessage]
    ,CASE [freq_type] WHEN 4 THEN 'Occurs every ' + CAST([freq_interval] AS VARCHAR(3)) + ' day(s)' WHEN 8 THEN 'Occurs every ' + CAST([freq_recurrence_factor] AS VARCHAR(3)) + ' week(s) on ' + CASE WHEN [freq_interval] & 1 = 1 THEN 'Sunday' ELSE '' END + CASE WHEN [freq_interval] & 2 = 2 THEN ', Monday' ELSE '' END + CASE WHEN [freq_interval] & 4 = 4 THEN ', Tuesday' ELSE '' END + CASE WHEN [freq_interval] & 8 = 8 THEN ', Wednesday' ELSE '' END + CASE WHEN [freq_interval] & 16 = 16 THEN ', Thursday' ELSE '' END + CASE WHEN [freq_interval] & 32 = 32 THEN ', Friday' ELSE '' END + CASE WHEN [freq_interval] & 64 = 64 THEN ', Saturday' ELSE '' END WHEN 16 THEN 'Occurs on Day ' + CAST([freq_interval] AS VARCHAR(3)) + ' of every ' + CAST([freq_recurrence_factor] AS VARCHAR(3)) + ' month(s)' WHEN 32 THEN 'Occurs on ' + CASE [freq_relative_interval] WHEN 1 THEN 'First' WHEN 2 THEN 'Second' WHEN 4 THEN 'Third' WHEN 8 THEN 'Fourth' WHEN 16 THEN 'Last' END + ' ' + CASE [freq_interval] WHEN 1 THEN 'Sunday' WHEN 2 THEN 'Monday' WHEN 3 THEN 'Tuesday' WHEN 4 THEN 'Wednesday' WHEN 5 THEN 'Thursday' WHEN 6 THEN 'Friday' WHEN 7 THEN 'Saturday' WHEN 8 THEN 'Day' WHEN 9 THEN 'Weekday' WHEN 10 THEN
    'Weekend day' END + ' of every ' + CAST([freq_recurrence_factor] AS VARCHAR(3)) + ' month(s)' END AS [Recurrence]
    ,CASE [freq_subday_type] WHEN 1 THEN 'Occurs once at ' + STUFF(STUFF(RIGHT('000000' + CAST([active_start_time] AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':') WHEN 2 THEN 'Occurs every ' + CAST([freq_subday_interval] AS VARCHAR(3)) + ' Second(s) between ' + STUFF(STUFF(RIGHT('000000' + CAST([active_start_time] AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':') + ' & ' + STUFF(STUFF(RIGHT('000000' + CAST([active_end_time] AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':') WHEN 4 THEN 'Occurs every ' + CAST([freq_subday_interval] AS VARCHAR(3)) + ' Minute(s) between ' + STUFF(STUFF(RIGHT('000000' + CAST([active_start_time] AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':') + ' & ' + STUFF(STUFF(RIGHT('000000' + CAST([active_end_time] AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':') WHEN 8 THEN 'Occurs every ' + CAST([freq_subday_interval] AS VARCHAR(3)) + ' Hour(s) between ' + STUFF(STUFF(RIGHT('000000' + CAST([active_start_time] AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':') + ' & ' + STUFF(STUFF(RIGHT('000000' + CAST([active_end_time] AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':') END [Frequency]
FROM [msdb].[dbo].[sysjobs] AS [sJOB]
LEFT JOIN (
    SELECT [job_id]
        ,[run_date]
        ,[run_time]
        ,[run_status]
        ,[run_duration]
        ,[message]
        ,ROW_NUMBER() OVER (
            PARTITION BY [job_id] ORDER BY [run_date] DESC
            ,[run_time] DESC
            ) AS RowNumber
    FROM [msdb].[dbo].[sysjobhistory]
    WHERE [step_id] = 0
    ) AS [sJOBH] ON [sJOB].[job_id] = [sJOBH].[job_id]
    AND [sJOBH].[RowNumber] = 1
LEFT JOIN [msdb].[dbo].[sysjobschedules] AS [sJOBSCH] ON [sJOB].[job_id] = [sJOBSCH].[job_id]
LEFT JOIN [msdb].[dbo].[sysschedules] AS [sSCH] ON [sJOBSCH].[schedule_id] = [sSCH].[schedule_id]
WHERE [sJOB].[enabled] = 1
ORDER BY [JobName]

-- all Jobs
 SELECT [sJOB].[name] AS [JobName]
        ,CASE WHEN [run_date] IS NULL
        OR [run_time] IS NULL THEN NULL ELSE CAST(CAST([run_date] AS CHAR(8)) + ' ' + STUFF(STUFF(RIGHT('000000' + CAST([run_time] AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':') AS DATETIME) END AS [LastRunDateTime],
        STUFF(STUFF(RIGHT('000000' + CAST([run_duration] AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':') AS [LastRunDuration (HH:MM:SS)]
        ,[run_status]  ,[run_duration]  ,[message]
        ,ROW_NUMBER() OVER (
            PARTITION BY [sJOBH].[job_id] ORDER BY [run_date] DESC
            ,[run_time] DESC ) AS RowNumber
    FROM [msdb].[dbo].[sysjobhistory] [sJOBH] , [msdb].[dbo].[sysjobs] AS [sJOB]
    WHERE [sJOB].[job_id] = [sJOBH].[job_id] AND [step_id] = 0
    and run_duration > 600
    ORDER BY [run_date], [run_time]
```

## Table statistics

```sql
select count(*) as number, DatePhysical, dataareaid from inventtrans (nolock)
group by DatePhysical, dataareaid
order by number desc

select count(*) as number, Closed,dataareaid from InventSum (nolock)
Group by Closed, dataareaid

select count(*) as number, CreatedDate from SALESLINE (nolock)
group by CreatedDate
order by number desc

select USERID from SYSUSERLOG
where LOGOUTDATETIME > CONVERT(datetime, '2020-04-10', 120)
group by USERID

select COUNT(*) as RecordCount , TABLE_ ,
CASE
    WHEN a.LOGTYPE = 0 THEN 'Insert'
    WHEN a.LOGTYPE = 1 THEN 'Delete'
    WHEN a.LOGTYPE = 2 THEN 'Update'
END as LogType,
b.name from SYSDATABASELOG a, SQLDICTIONARY b
where b.tableid = a.table_ and b.FIELDID = 0
group by a.TABLE_, b.name, a.LOGTYPE
ORDER BY RecordCount DESC

--Records count by hour
DECLARE  @mOffset int
set @mOffset = DATEDIFF(mi,SYSUTCDATETIME(), SYSDATETIME())

select count(*) as 'Records count', 
CONVERT(date, DATEADD(mi, @mOffset, CREATEDDATETIME)) as 'Date', DATEPART(HOUR, DATEADD(mi, @mOffset, CREATEDDATETIME)) as 'Hour' from SalesTable
where DATEADD(mi, @mOffset, CREATEDDATETIME) >= '2020-09-15'
group by CONVERT(date, DATEADD(mi, @mOffset, CREATEDDATETIME)),
DATEPART(HOUR, DATEADD(mi, @mOffset, CREATEDDATETIME))
ORDER BY 
CONVERT(date, DATEADD(mi, @mOffset, CREATEDDATETIME)),
DATEPART(HOUR, DATEADD(mi, @mOffset, CREATEDDATETIME))

--Is margin alert enabled(can affect SO performance)
select DATAAREAID from SALESPARAMETERS where MCREnableMarginAlert <> 0
--Mixed statuses for WMS locations check
select * from WHSLocationProfile where AllowMixedStatus = 0 or ALLOWMIXEDBATCHES = 0 or ALLOWMIXEDITEMS = 0
--Check the number of client sessions
select * from SYSCLIENTSESSIONS
```

## sp_Blitz

https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit

# Review database status

## Index defragmentation

```sql
declare @dbid int;
declare @objectid int;

set @dbid = DB_ID();
set @objectid =  OBJECT_ID(N'dbo.InventTrans')

SELECT a.index_id, name, avg_fragmentation_in_percent
FROM sys.dm_db_index_physical_stats(
 @dbid,
@objectid,NULL, NULL , NULL ) AS a
    JOIN sys.indexes AS b ON a.object_id = b.object_id AND a.index_id = b.index_id;
```

## Missing indexes

```sql
SELECT    object_name(d.object_id) as tabname, database_id, equality_columns, inequality_columns, avg_user_impact, included_columns,
  unique_compiles, user_seeks, user_scans, last_user_seek, last_user_scan,p.rows AS [Table Rows]
FROM    sys.dm_db_missing_index_details d
INNER JOIN sys.dm_db_missing_index_groups g
    ON    d.index_handle = g.index_handle
INNER JOIN sys.dm_db_missing_index_group_stats s
    ON    g.index_group_handle = s.group_handle
CROSS APPLY (SELECT TOP 1 rows from  sys.partitions WITH (NOLOCK) WHERE sys.partitions.[object_id] = d.[object_id]) AS p
WHERE    database_id = db_id()
ORDER BY  avg_total_user_cost * avg_user_impact *(user_seeks + user_scans) DESC
```

## Unused indexes

```sql
select object_name(us.[object_id]) as Table_Name, ix.name as Index_name, ix.type_desc, user_seeks, user_scans, user_lookups, user_updates
from sys.dm_db_index_usage_stats us
inner join sys.indexes ix on ix.[object_id] = us.[object_id] and ix.index_id = us.index_id
where us.database_id = db_id() and ix.type_desc <> 'HEAP' and
(us.user_seeks + us.user_scans + us.user_lookups) = 0 and us.user_updates <>0
order by 7 desc
```

## Disk I / o

```sql
USE  master
GO
SELECT TOP 10    DB_NAME(saf.dbid)            AS [Database]
    ,    saf.name                AS [Name]
    ,    vfs.BytesRead/1048576            AS [Read (MB)]
    ,    vfs.BytesWritten/1048576        AS [Write (MB)]
    ,    saf.filename                 AS [File]
FROM        sysaltfiles                AS saf
JOIN    ::fn_virtualfilestats(NULL,NULL)        AS vfs
ON        vfs.dbid = saf.dbid
AND        vfs.fileid = saf.fileid
AND        saf.dbid NOT IN (1,3,4)
ORDER BY    vfs.BytesRead/1048576 + BytesWritten/1048576 DESC
GO

SELECT   SUBSTRING(saf.physical_name, 1, 1)        AS [Disk]
       , SUM(vfs.num_of_bytes_read/1048576)        AS [Read (MB)]
       , SUM(vfs.num_of_bytes_written/1048576)        AS [Write (MB)]
FROM     sys.master_files   AS saf
JOIN     sys.dm_io_virtual_file_stats(NULL,NULL) AS vfs
ON     vfs.database_id = saf.database_id
AND     vfs.file_id = saf.file_id
AND     saf.database_id NOT IN (1,3,4)
AND     saf.type < 2
GROUP BY SUBSTRING(saf.physical_name, 1, 1)
ORDER BY [Disk]
GO
```

## Wait statistics

```sql
WITH [Waits]
AS (SELECT wait_type, wait_time_ms/ 1000.0 AS [WaitS],
          (wait_time_ms - signal_wait_time_ms) / 1000.0 AS [ResourceS],
           signal_wait_time_ms / 1000.0 AS [SignalS],
           waiting_tasks_count AS [WaitCount],
           100.0 *  wait_time_ms / SUM (wait_time_ms) OVER() AS [Percentage],
           ROW_NUMBER() OVER(ORDER BY wait_time_ms DESC) AS [RowNum]
    FROM sys.dm_os_wait_stats WITH (NOLOCK)
    WHERE [wait_type] NOT IN (
        N'BROKER_EVENTHANDLER', N'BROKER_RECEIVE_WAITFOR', N'BROKER_TASK_STOP',
        N'BROKER_TO_FLUSH', N'BROKER_TRANSMITTER', N'CHECKPOINT_QUEUE',
        N'CHKPT', N'CLR_AUTO_EVENT', N'CLR_MANUAL_EVENT', N'CLR_SEMAPHORE',
        N'DBMIRROR_DBM_EVENT', N'DBMIRROR_EVENTS_QUEUE', N'DBMIRROR_WORKER_QUEUE',
        N'DBMIRRORING_CMD', N'DIRTY_PAGE_POLL', N'DISPATCHER_QUEUE_SEMAPHORE',
        N'EXECSYNC', N'FSAGENT', N'FT_IFTS_SCHEDULER_IDLE_WAIT', N'FT_IFTSHC_MUTEX',
        N'HADR_CLUSAPI_CALL', N'HADR_FILESTREAM_IOMGR_IOCOMPLETION', N'HADR_LOGCAPTURE_WAIT',
        N'HADR_NOTIFICATION_DEQUEUE', N'HADR_TIMER_TASK', N'HADR_WORK_QUEUE',
        N'KSOURCE_WAKEUP', N'LAZYWRITER_SLEEP', N'LOGMGR_QUEUE',
        N'MEMORY_ALLOCATION_EXT', N'ONDEMAND_TASK_QUEUE',
        N'PARALLEL_REDO_DRAIN_WORKER', N'PARALLEL_REDO_LOG_CACHE', N'PARALLEL_REDO_TRAN_LIST',
        N'PARALLEL_REDO_WORKER_SYNC', N'PARALLEL_REDO_WORKER_WAIT_WORK',
        N'PREEMPTIVE_HADR_LEASE_MECHANISM', N'PREEMPTIVE_SP_SERVER_DIAGNOSTICS',
        N'PREEMPTIVE_OS_LIBRARYOPS', N'PREEMPTIVE_OS_COMOPS', N'PREEMPTIVE_OS_CRYPTOPS',
        N'PREEMPTIVE_OS_PIPEOPS', N'PREEMPTIVE_OS_AUTHENTICATIONOPS',
        N'PREEMPTIVE_OS_GENERICOPS', N'PREEMPTIVE_OS_VERIFYTRUST',
        N'PREEMPTIVE_OS_FILEOPS', N'PREEMPTIVE_OS_DEVICEOPS', N'PREEMPTIVE_OS_QUERYREGISTRY',
        N'PREEMPTIVE_OS_WRITEFILE',
        N'PREEMPTIVE_XE_CALLBACKEXECUTE', N'PREEMPTIVE_XE_DISPATCHER',
        N'PREEMPTIVE_XE_GETTARGETSTATE', N'PREEMPTIVE_XE_SESSIONCOMMIT',
        N'PREEMPTIVE_XE_TARGETINIT', N'PREEMPTIVE_XE_TARGETFINALIZE',
        N'PWAIT_ALL_COMPONENTS_INITIALIZED', N'PWAIT_DIRECTLOGCONSUMER_GETNEXT',
        N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
        N'QDS_ASYNC_QUEUE',
        N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP', N'REQUEST_FOR_DEADLOCK_SEARCH',
        N'RESOURCE_QUEUE', N'SERVER_IDLE_CHECK', N'SLEEP_BPOOL_FLUSH', N'SLEEP_DBSTARTUP',
        N'SLEEP_DCOMSTARTUP', N'SLEEP_MASTERDBREADY', N'SLEEP_MASTERMDREADY',
        N'SLEEP_MASTERUPGRADED', N'SLEEP_MSDBSTARTUP', N'SLEEP_SYSTEMTASK', N'SLEEP_TASK',
        N'SLEEP_TEMPDBSTARTUP', N'SNI_HTTP_ACCEPT', N'SP_SERVER_DIAGNOSTICS_SLEEP',
        N'SQLTRACE_BUFFER_FLUSH', N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', N'SQLTRACE_WAIT_ENTRIES',
        N'WAIT_FOR_RESULTS', N'WAITFOR', N'WAITFOR_TASKSHUTDOWN', N'WAIT_XTP_HOST_WAIT',
        N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG', N'WAIT_XTP_CKPT_CLOSE', N'WAIT_XTP_RECOVERY',
        N'XE_BUFFERMGR_ALLPROCESSED_EVENT', N'XE_DISPATCHER_JOIN',
        N'XE_DISPATCHER_WAIT', N'XE_LIVE_TARGET_TVF', N'XE_TIMER_EVENT')
    AND waiting_tasks_count > 0)
SELECT
    MAX (W1.wait_type) AS [WaitType],
    CAST (MAX (W1.Percentage) AS DECIMAL (5,2)) AS [Wait Percentage],
    CAST ((MAX (W1.WaitS) / MAX (W1.WaitCount)) AS DECIMAL (16,4)) AS [AvgWait_Sec],
    CAST ((MAX (W1.ResourceS) / MAX (W1.WaitCount)) AS DECIMAL (16,4)) AS [AvgRes_Sec],
    CAST ((MAX (W1.SignalS) / MAX (W1.WaitCount)) AS DECIMAL (16,4)) AS [AvgSig_Sec],
    CAST (MAX (W1.WaitS) AS DECIMAL (16,2)) AS [Wait_Sec],
    CAST (MAX (W1.ResourceS) AS DECIMAL (16,2)) AS [Resource_Sec],
    CAST (MAX (W1.SignalS) AS DECIMAL (16,2)) AS [Signal_Sec],
    MAX (W1.WaitCount) AS [Wait Count],
    CAST (N'https://www.sqlskills.com/help/waits/' + W1.wait_type AS XML) AS [Help/Info URL]
FROM Waits AS W1
INNER JOIN Waits AS W2
ON W2.RowNum <= W1.RowNum
GROUP BY W1.RowNum, W1.wait_type
HAVING SUM (W2.Percentage) - MAX (W1.Percentage) < 99 -- percentage threshold
OPTION (RECOMPILE);
```

# Database monitoring

## Database locks

```sql
select qs.spid,
        qs.status, qs.blocked,
        dbname=db_name(qs.dbid),
        SUBSTRING(qt.text,qs.stmt_start/2 +1,
        (case when qs.stmt_end = -1 then len(convert(nvarchar(max), qt.text)) * 2
        else qs.stmt_end end -qs.stmt_start)/2) as QueryText,
        qs.open_tran, qs.waitresource, qs.waittype,
         qs.waittime, qs.cmd, qs.lastwaittype, qs.cpu, qs.physical_io,
         qs.memusage,
         last_batch=convert(varchar(26), last_batch,121),
         login_time=convert(varchar(26), login_time,121),net_address,
         qs.net_library, qs.dbid, qs.ecid, qs.kpid, qs.hostname, qs.hostprocess,
         qs.loginame, qs.program_name, qs.nt_domain, qs.nt_username, qs.uid, qs.sid
      from master.dbo.sysprocesses as qs
      cross apply sys.dm_exec_sql_text(qs.sql_handle) as qt
      where blocked!=0 or waittype != 0x0000
order by qs.dbid
```

## Cursors for the session

```sql
Select cursor_id,
worker_time,
reads,
writes,
dormant_duration,
[text]
from sys.dm_exec_cursors (0) cross apply
sys.dm_exec_sql_text(sql_handle)
where session_id=80
```

The following query gets to the original SQL query:

```sql
SELECT c.session_id, c.creation_time, c.reads, c.writes,
sp.blocked, sp.waitresource, loginame = UPPER(sp.loginame),
dbname = DB_NAME(sp.dbid), sp.status, open_tran = NULLIF(sp.open_tran, 0),
application = UPPER(program_name), command = sp.cmd, waittime = NULLIF(sp.waittime, 0),
sp.hostname, t.text as curtext, y.text as proctext
FROM sys.dm_exec_cursors (0) c
CROSS APPLY sys.dm_exec_sql_text (c.sql_handle) t
       join sysprocesses sp on c.session_id=sp.spid
cross apply sys.dm_exec_sql_text(sp.sql_handle) y
where y.text like 'FETCH%'
order by c.reads desc
```

## Show SQL query for the AX user

https://blogs.msdn.microsoft.com/amitkulkarni/2011/08/10/finding-user-sessions-from-spid-in-dynamics-ax-2012/

- Navigate to HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\services\Dynamics Server\6.0\01\Original (installed configuration). The last key, Original (installed configuration), is the key name for the current server configuration. If your system uses a different configuration that the original installed configuration, navigate to the currently active configuration.
- Create a string registry value called ‘connectioncontext’ and set the value to 1.
- Restart the AOS.

```sql
select cast(context_info as varchar(128)) as ci , *
from sys.dm_exec_sessions
where program_name like N'%Dynamics%'
and cast(context_info as varchar(128)) like N'%user1%'
```

## Show current trance flags

```sql
DBCC TRACESTATUS(-1)

GO

DBCC TRACESTATUS()

GO
```

## Clear SQL server cache

```sql
CHECKPOINT;
GO
DBCC DROPCLEANBUFFERS;
GO
DBCC FREEPROCCACHE
GO

update statistics WMSPICKINGROUTE with fullscan
ALTER INDEX ALL ON InventSum REBUILD
```

## Clear AX cache

```sql
update SYSSQMSETTINGS SET GLOBALGUID = '{00000000-0000-0000-0000-000000000000}'

```

(restart AOS after that)

## Longest transactions

```sql
SELECT b.session_id AS [Session ID],
       CAST(Db_name(a.database_id) AS VARCHAR(20)) AS [Database Name],
       c.command,
       Substring(st.TEXT, ( c.statement_start_offset / 2 ) + 1,
       ( (
       CASE c.statement_end_offset
        WHEN -1 THEN Datalength(st.TEXT)
        ELSE c.statement_end_offset
       END
       -
       c.statement_start_offset ) / 2 ) + 1)
       statement_text,
       Coalesce(Quotename(Db_name(st.dbid)) + N'.' + Quotename(
       Object_schema_name(st.objectid,
                st.dbid)) +
                N'.' + Quotename(Object_name(st.objectid, st.dbid)), '')
       command_text,
       c.wait_type,
       c.wait_time,
       a.database_transaction_begin_time,
       a.database_transaction_log_bytes_used / 1024.0 / 1024.0 AS [MB used],
       a.database_transaction_log_bytes_used_system / 1024.0 / 1024.0 AS [MB used system],
       a.database_transaction_log_bytes_reserved / 1024.0 / 1024.0 AS [MB reserved],
       a.database_transaction_log_bytes_reserved_system / 1024.0 / 1024.0 AS [MB reserved system],
       a.database_transaction_log_record_count AS [Record count]
FROM   sys.dm_tran_database_transactions a
       JOIN sys.dm_tran_session_transactions b
         ON a.transaction_id = b.transaction_id
       JOIN sys.dm_exec_requests c
           CROSS APPLY sys.Dm_exec_sql_text(c.sql_handle) AS st
         ON b.session_id = c.session_id
         order by [Database Name], [Record count]
```

## Get Top SQL

```sql
SELECT TOP 50
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

qp.query_plan
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
CROSS APPLY sys.dm_exec_plan_attributes(qs.plan_handle) qpa
where attribute = 'dbid'
ORDER BY qs.total_logical_reads DESC -- logical reads
-- ORDER BY qs.total_logical_writes DESC -- logical writes
--ORDER BY qs.total_worker_time DESC -- CPU time
--ORDER BY qs.total_physical_reads desc

-- DBCC FREEPROCCACHE to reset the counter
```

# Database changes

## Create a plan guide

```sql
EXEC sp_create_plan_guide @name = N'[AX_InventItemPriceDim]', @stmt = N'SELECT TOP 1 T1.ITEMID,T1.VERSIONID,T1.PRICETYPE,T1.INVENTDIMID,T1.MARKUP,T1.PRICEUNIT,T1.PRICE,T1.PRICECALCID,T1.UNITID,T1.PRICEALLOCATEMARKUP,T1.PRICEQTY,T1.STDCOSTTRANSDATE,T1.STDCOSTVOUCHER,T1.COSTINGTYPE,T1.ACTIVATIONDATE,T1.PRICESECCUR_RU,T1.MARKUPSECCUR_RU,T1.MODIFIEDDATETIME,T1.CREATEDDATETIME,T1.RECVERSION,T1.PARTITION,T1.RECID FROM INVENTITEMPRICE T1 WHERE (((T1.PARTITION=@P1) AND (T1.DATAAREAID=@P2)) AND (((T1.ITEMID=@P3) AND (T1.PRICETYPE=@P4)) AND (T1.ACTIVATIONDATE<=@P5))) AND EXISTS (SELECT TOP 1 ''x'' FROM INVENTDIM T2 WHERE (((T2.PARTITION=@P6) AND (T2.DATAAREAID=@P7)) AND ((T2.INVENTDIMID=T1.INVENTDIMID) AND (T2.INVENTSITEID=@P8)))) ORDER BY T1.ACTIVATIONDATE DESC,T1.CREATEDDATETIME DESC',
@type = N'SQL',
@module_or_batch = null,
@params = N'@P1 bigint,@P2 nvarchar(5),@P3 nvarchar(21),@P4 int,@P5 datetime2,@P6 bigint,@P7 nvarchar(5),@P8 nvarchar(11)',
@hints = N'OPTION (OPTIMIZE FOR UNKNOWN)'
@hints = N'OPTION(TABLE HINT (B, INDEX(I_698DIMIDIDX)), TABLE HINT ( a, INDEX(I_174ITEMDIMIDX)), loop join)'
```

## Delete a plan from the cache

```sql
select top 100
    plan_handle, st.text, qp.*
from
    sys.dm_exec_cached_plans
cross apply
    sys.dm_exec_sql_text(plan_handle) as st
cross apply
    sys.dm_exec_query_plan(plan_handle) as qp
where text like N'%SELECT TOP 1 A.VENDGROUP,A.PURCHID,A.ORDERACCOUNT,A.INVOICEACCOUNT,A.INVOICEID,A.INVOICEDATE,A.DUEDATE,A.CASHDISC,A.CASHDISCDATE,A.QTY,A.VOLUME,A.WEIGHT,A.SUMLINEDISC,A.PREPAYMENT,A.SALESBALANCE,A.ENDDISC,A.INVOICEAMOUNT,A.CURRENCYCODE,A.EXCHRATE,A.ENTERPRISENUMBER,A.RETURNITEMNUM,A.TAXROUNDOFF,A.LEDGERVOUCHER,A.DIMENSION,A.DIMENSION2_,A.DIMENSION3_,A.DIMENSION4_,A.TAXPRINTONINVOICE,A.TAXSPECIFYBYLINE,A.DOCUMENTNUM,A.DOCUMENTDATE,A.COUNTRYREGIONID,A.INTRASTATDISPATCH,A.INVOICEROUNDOFF,A.SUMMARKUP,A.PAYMID,A.TAXGROUP,A.CASHDISCCODE,A.PAYMENT,A.POSTINGPROFILE,A.PAYMENTSCHED,A.INTERCOMPANYPOSTED,A.PURCHASETYPE,A.SUMTAX,A.PARMID,A.EXCHRATESECONDARY,A.TRIANGULATION,A.ITEMBUYERGROUPID,A.VATNUM,A.INTERNALINVOICEID,A.NUMBERSEQUENCEGROUP,A.INCLTAX,A.PAYMDAYID,A.DLVTERM,A.DLVMODE,A.FIXEDDUEDATE,A.INTERCOMPANYCOMPANYID,A.INTERCOMPANYSALESID,A.INTERCOMPANYLEDGERVOUCHER,A.PROFORMA,A.LANGUAGEID,A.INVOICEAMOUNTMST,A.SUMMARKUPMST,A.ENDDISCMST,A.REVERSECHARGE_UK,A.PURCHRECEIPTDATE_W,A.VATONPAYMENT_RU,A.CORRECT_RU,A.INVENTPROFILETYPE_RU,A.CORRECTEDINVOICEID_RU,A.CORRECTEDINVOICEDATE_RU,A.EUSALESLIST_HU,A.SUMTAX_W,A.EXCHRATE_W,A.INVENTBAILEERECEIPTREPORTID_RU,A.REFORIGINALINVOICE_RU,A.CORRECTIONTYPE_RU,A.NONREALREVENUE_RU,A.OFFSESSIONID_RU,A.CONSIGNEEACCOUNT_RU,A.CONSIGNORACCOUNT_RU,A.FACTUREDFULLY_RU,A.ATTORNEYISSUEDNAME_RU,A.ATTORNEYID_RU,A.ATTORNEYDATE_RU,A.RCONTRACTCODE,A.RCONTRACTACCOUNT,A.LISTCODE_EE,A.EUINVOICERECID_PL,A.KAR_APPLICIMPORTEDGOODSEX50001,A.KAR_APPLICIMPORTEDGOODSEX50004,A.KAR_INVENTTRANSFERCREATED,A.KAR_RELATEDTRANSFERSHIPPED,A.CREATEDDATETIME,A.DEL_CREATEDTIME,A.CREATEDBY,A.CREATEDTRANSACTIONID,A.RECVERSION,A.RECID FROM VENDINVOICEJOUR A WHERE ((DATAAREAID=N''ru'') AND (((((INVOICEID=@P1) AND (INVOICEDATE=@P2)) AND (PURCHID=@P3)) AND (NUMBERSEQUENCEGROUP=@P4)) AND (INTERNALINVOICEID=@P5)))%'

DBCC FREEPROCCACHE (0x060005005BB88A134041B2A6120000000000000000000000)
```

## Find disabled tables

Normal tables that were disabled by the config key. In this case for every call AX created a temporary table, that affects the performance

Check are there any table in the DB cache

```sql
declare @p1 nvarchar(100)
declare @pTxt nvarchar(1000)
set @p1 = 'INSERT INTO tempdb."DBO".t';

select tabId , b.[name] from (select top 10000
    SUBSTRING ( st.text ,CHARINDEX(@p1, st.text)+len(@p1) , CHARINDEX('_', st.text) - CHARINDEX(@p1, st.text)-len(@p1) ) as tabId
from
    sys.dm_exec_cached_plans
cross apply
    sys.dm_exec_sql_text(plan_handle) as st
where text like (N'%' + @p1 + N'%') and
CHARINDEX('_', st.text) - CHARINDEX(@p1, st.text)-len(@p1) > 1) a, sqldictionary b
where a.tabId <> '' and TRY_CONVERT (int , a.tabId )= b.TABLEID and b.FIELDID = 0
group by a.tabId, b.[name]
```

```csharp
static boolean dev_isTableEnabled(Common _table)
{
    boolean     res = true;
    DictTable   dictTable;
    ;
    if (! _table.TableId || _table.isTmp())
    {
        res = false;
    }
    else
    {
        dictTable = new DictTable(_table.TableId);

        if (dictTable && dictTable.configurationKeyId() && ! isConfigurationkeyEnabled(dictTable.configurationKeyId()))
        {
            res = false;
        }
    }
    return res;
}
if (! dev_isTableEnabled(assetParameters))
{
    return assetParameters;
}
```

```sql
CREATE TABLE tempdb."DBO".t1162_5E2D5DA7EC324CC6BF0BA2281C0D58B8  (KEY_ INT NOT NULL DEFAULT 0 ,DEPRECIATIONMIN NUMERIC(32,16) NOT NULL DEFAULT 0 ,MULTIACQUISITION INT NOT NULL DEFAULT 0 ,ADDITIONALACQDEPRECIATION INT
```

## Index maintenance

https://ola.hallengren.com/

# Helper AX jobs

## Enabling tracing

```csharp
static void TRUD_SetSQLMonitorFlag(Args _args)
{
    #LOCALMACRO.FLAG_TraceInfoQueryTable         (1 << 11) #ENDMACRO
    #LOCALMACRO.FLAG_SQLTrace                    (1 << 8) #ENDMACRO
    #LOCALMACRO.FLAG_TraceInfoDeadLockTable      (1 << 15) #ENDMACRO

    UserInfo        userInfo;
    ;
    //To remove use ^
    while select userInfo
        where userInfo.id == 'denis'

    {
        userInfo.debugInfo      = userInfo.debugInfo | #FLAG_SQLTrace;
        userInfo.traceInfo      = userInfo.traceInfo | #FLAG_TraceInfoQueryTable;
        userInfo.traceInfo      = userInfo.traceInfo | #FLAG_TraceInfoDeadLockTable;
        userInfo.querytimeLimit = 2000;
        userInfo.skipTTSCheck(true);
        userInfo.update();
    }
}
```

## Delete similar traces

```csharp
//delete similar traces
static void dev1_deletesystrace(Args _args)
{
    SysTraceTableSQL        sysTraceTableSQL;
    SysTraceTableSQL        sysTraceTableSQLOrig;
    int                     rows;
    ;
    select sysTraceTableSQLOrig
        where sysTraceTableSQLOrig.RecId == 134324;

    while select sysTraceTableSQL
        where sysTraceTableSQL.Category     == SQLTraceCategory::QueryTime &&
              sysTraceTableSQL.createdDate  == sysTraceTableSQLOrig.createdDate &&
              sysTraceTableSQL.RecId        != sysTraceTableSQLOrig.RecId
    {
        if (
            sysTraceTableSQL.Statement == sysTraceTableSQLOrig.Statement &&
            sysTraceTableSQL.callStack == sysTraceTableSQLOrig.callStack
          )
        {
            rows++;
            sysTraceTableSQL.skipTTSCheck(true);
            //sysTraceTableSQL.delete();
        }

    }
    info(strFmt("%1", rows));
}
```

## SysdatabaseLog size

```csharp
static void dev1_sysdatabaseLog(Args _args)
{
    SysDatabaseLog  sysdatabaseLog;
    TextBuffer      tb = new TextBuffer();
    ;
    tb.appendText(strFmt("%1\t%2\t%3\n",
    "Table",    "LogType",    "Record Count"));
    while select count(recid) from sysdatabaseLog
        group by LogType, table
    {
    tb.appendText(strFmt("%1\t%2\t%3\n", tableid2name(sysdatabaseLog.table), sysdatabaseLog.LogType, sysdatabaseLog.RecId));
    }
    tb.toClipboard();
}

static void trud_copyBatchInfo(Args _args)
{
    Batch  batch;
    TextBuffer      tb = new TextBuffer();
    ;
    tb.appendText(strFmt("%1\t%2\t%3\t%4\t%5\t%6\t%7\t%8\n",
    "Batch job ID" ,   "Status"  ,  "Job description" ,   "Actual start date/time" ,  
     "End date/time" ,   "Company" ,   "Partition Key" ,   "User ID"));
    while select batch
        where batch.EndDate > 30\12\2018
    {
        tb.appendText(strFmt(strFmt("%1\t%2\t%3\t%4\t%5\t%6\t%7\t%8\n",
            batch.RecId, batch.Status, batch.ClassDescription(), strFmt("%1 %2", batch.StartDate, time2str(batch.startTime, 1, 1)),
            strFmt("%1 %2", batch.EndDate, time2str(batch.endtime,1,1)), batch.Company, batch.TableId, batch.CreatedBy)
             ));
    }
    Box::info("done");
    tb.toClipboard();
}
```

## Number sequences check

```csharp
static void numberSeqCheck(Args _args)
{
    NumberSequenceTable     numberSequenceTable;
    NumberSequenceReference numberSequenceReference, numberSequenceReference2;
    NumberSequenceScope     numberSequenceScope;
    DataArea                dataArea;
    real  ratio;
    int     i;
    ;

    info("Less that 25%");
    while select numberSequenceTable
    {
        ratio = (numberSequenceTable.Highest - numberSequenceTable.NextRec ) / (numberSequenceTable.Highest - numberSequenceTable.Lowest) ;
        if (ratio < 0.25 )
        {
            info(strFmt("Code %1, txt %2, Lowest %3, Highest %4, NextRec %5", numberSequenceTable.NumberSequence, numberSequenceTable.Txt,
                           numberSequenceTable.Lowest,  numberSequenceTable.Highest, numberSequenceTable.NextRec));
        }
    }
    info("Continuous");
    numberSequenceTable = null;
    while select numberSequenceTable
        where numberSequenceTable.Continuous &&
             (numberSequenceTable.NextRec > numberSequenceTable.Lowest + 1000)
    {
        info(strFmt("Code %1, txt %2, Lowest %3, Highest %4, NextRec %5", numberSequenceTable.NumberSequence, numberSequenceTable.Txt,
                           numberSequenceTable.Lowest,  numberSequenceTable.Highest, numberSequenceTable.NextRec));
    }
    info("Not existing");
    numberSequenceTable = null;
    ttsBegin;
    while select forUpdate numberSequenceTable
    join numberSequenceReference
        where numberSequenceReference.NumberSequenceId == numberSequenceTable.RecId
    join numberSequenceScope
        where numberSequenceScope.RecId == numberSequenceReference.NumberSequenceScope &&
              numberSequenceScope.dataArea
    notexists join dataArea
        where dataArea.id == numberSequenceScope.dataArea
    {
        numberSequenceReference2 = null;
        select firstonly numberSequenceReference2
            where numberSequenceReference2.NumberSequenceId == numberSequenceTable.RecId &&
                  numberSequenceReference2.RecId !=  numberSequenceReference.RecId;
        if (! numberSequenceReference2.RecId)
        {
            if (i < 100)
            {
            info(strFmt("Code %1, txt %2, Lowest %3, Highest %4, NextRec %5", numberSequenceTable.NumberSequence, numberSequenceTable.Txt,
                           numberSequenceTable.Lowest,  numberSequenceTable.Highest, numberSequenceTable.NextRec));
            }
            i++;
            /*
            numberSequenceScope.dodelete();
            numberSequenceReference.dodelete();
            numberSequenceTable.doDelete();
            */
        }
    }
    ttsCommit;
    info(strFmt("Total number %1", i));
}
```

## Check the entire table cache

```csharp
#AOT
static void trud_checkCache(Args _args) {
    TreeNode              treeNodeTable;
    TreeNodeIterator      treeNodeIteratorTable;
    DictTable             dictTable;
    Common                anyRecord;
    SysOperationProgress  operationProgress = new SysOperationProgress ();
    ;
    treeNodeTable         = infolog.findNode(#TablesPath);
    treeNodeIteratorTable = treeNodeTable.aotiterator();
    treeNodeTable         = treeNodeIteratorTable.next();

    operationProgress.setCaption("Check...");
    operationProgress.setTotal(7000);  //approximately

    while (treeNodeTable)
    {
        //if (treeNodeTable.treeNo == TreeNodeType::  UtilElementType::Table)
        {
            dictTable = new DictTable(treeNodeTable.applObjectId());
            if (dictTable && dictTable.cacheLookup() == RecordCacheLevel::EntireTable)
            {
                anyRecord = null;
                anyRecord = dictTable.makeRecord();
                select crossCompany count(RecId) from anyRecord;
                if (anyRecord.RecId > 1000)
                {
                    info(strFmt("%1, %2", dictTable.name(), anyRecord.RecId));
                }
            }
        }
        operationProgress.incCount();
        treeNodeTable = treeNodeIteratorTable.next();
    }
}
```

# Performance hints

## CPUID

1. Download the <http://www.roylongbottom.org.uk/win64.zip>
2. Run the program dhry164int32.exe example 10 times

dhry264int64  
12621 E5-2637 v2   8467 E5-2640 v2 (2GHz),  10082 E5-2640(2.5GHz)

dhry164int32
27605 E5-2637 v2,     18581 E5-2640 v2 (2GHz),  21130 E5-2640(2.5GHz)

Crystal disk mark

[How to Use CrystalDiskMark 7 to Test Your SQL Server’s Storage](https://www.brentozar.com/archive/2019/11/how-to-use-crystaldiskmark-7-to-test-your-sql-servers-storage/)

8 RAID 10 Inner RAID

 ![1557246894814](Images/CrystalDiskMark.png)

## Delete from a large table

```sql
IF OBJECT_ID('tempdb..#recordsToDelete') IS NOT NULL DROP TABLE #recordsToDelete
IF OBJECT_ID('tempdb..#temp_hash') IS NOT NULL
    DROP TABLE #temp_hash

CREATE TABLE #temp_hash (RECID   BIGINT)

declare @step int
declare @isLastStep int = 0;

WHILE (@isLastStep = 0)
BEGIN
    select top 1000000 RECID into #recordsToDelete
    FROM [dbo].ZINFOLOGHISTORY AS hashtbl            --TABLE HERE
    WHERE hashtbl.CREATEDDATETIME <(GETDATE() -30);

    IF (@@ROWCOUNT < 1000000) SET @isLastStep = 1
    CREATE NONCLUSTERED INDEX [##_RECID] ON #recordsToDelete (RECID ASC)

    set @step= 0
    WHILE (@step < 100)
    BEGIN
        SET @step = @step + 1
        TRUNCATE TABLE #temp_hash
        INSERT INTO #temp_hash(RECID) SELECT TOP 10000 RECID FROM  #recordsToDelete;
        IF (@@ROWCOUNT = 0) break;

        --------------------------------------------------------------
        delete FROM [dbo].ZINFOLOGHISTORY from [dbo].ZINFOLOGHISTORY  AS hs  --TABLE HERE
        INNER JOIN #temp_hash AS JN ON hs.RECID = JN.RECID
        ----------------------------

        delete from #recordsToDelete from #recordsToDelete as dt inner join #temp_hash as dl
        on dl.RECID =dt.RECID
    END
    DROP TABLE #recordsToDelete
END
DROP TABLE #temp_hash;

--Another option (about 30sec per 100k lines)
declare @rowCount int = -1;
declare @curStep int = 0

while(@rowCount <> 0 AND @curStep < 10000) begin
    WITH Comments_ToBeDeleted AS (
    SELECT TOP 10000 *
    FROM BatchJobHistory
    --ORDER BY CREATEDDATETIME
    )
    DELETE FROM Comments_ToBeDeleted
    WHERE CREATEDDATETIME <(GETDATE() - 30)
    set @rowCount = @@rowCount;
    set @curStep = @curStep + 1;
end
```

## Blocking alert

```sql
DECLARE @ThresholdTimeMS INT = 600
DECLARE @ThresholdNumOfLocks INT = 0
DECLARE @NumOfLocks INT
DECLARE @LocksTime INT

SELECT @NumOfLocks = count(*), @LocksTime = max(wait_duration_ms)
FROM sys.dm_os_waiting_tasks
WHERE blocking_session_id <> 0  
AND [wait_type] LIKE N'LCK_%'

IF @NumOfLocks > @ThresholdNumOfLocks AND @LocksTime > @ThresholdTimeMS
    BEGIN
        DECLARE @Msg NVARCHAR(max)
        DECLARE @HTMLStr NVARCHAR(max)

        SET @Msg = N'Blocking alert. Blocked sessions:'
            + CAST(@NumOfLocks AS NVARCHAR(10))
            + N' Blocked time:'
            + CAST(@LocksTime / 1000 AS NVARCHAR(10))
            + N' sec';


        DECLARE @oper_email NVARCHAR(100)
        SET @oper_email = (SELECT email_address from msdb.dbo.sysoperators WHERE name = N'OperatorName')

        DECLARE @body NVARCHAR(MAX)
        SET     @body = N'<table>'
            + N'<tr><th>session_id</th><th>wait_duration_ms</th><th>wait_type</th><th>blocking_session_id</th><th>resource_description</th><th>program_name</th><th>text</th></tr>'
            + CAST((
                SELECT   w.session_id  AS td
                         ,w.wait_duration_ms  AS td
                         ,w.wait_type  AS td
                         ,w.blocking_session_id  AS td
                         ,w.resource_description  AS td
                         ,s.program_name  AS td
                         ,t.text  AS td
                FROM sys.dm_os_waiting_tasks w
        INNER JOIN sys.dm_exec_sessions s
        ON w.session_id = s.session_id
        INNER JOIN sys.dm_exec_requests r
        ON s.session_id = r.session_id
        OUTER APPLY sys.dm_exec_sql_text (r.sql_handle) t
        WHERE s.is_user_process = 1
        AND w.[wait_type] LIKE N'LCK_%'
                    FOR XML RAW('tr'), ELEMENTS
            ) AS NVARCHAR(MAX))
            + N'</table>'

        SET @body = REPLACE(@body, '<tdc>', '<td class="center">')
        SET @body = REPLACE(@body, '</tdc>', '</td>')

        SET @HTMLStr = N'<html><body>' + @Msg + N'<br><br>' + @body + N'</body></html>';

        SELECT @HTMLStr  --DEBUG
        SET @oper_email = 'trud81@gmail.com'  --DEBUG

        EXEC msdb.dbo.sp_send_dbmail
            @recipients = @oper_email,
            @subject = @Msg,
            @body = @HTMLStr,
            @body_format = 'HTML' ;

        --RAISERROR (911421,10,1,@msg) WITH LOG;
    END
```

http://poorsql.com/

## Blocking in AX

https://denistrunin.com/understanding-sql-blocking/

## Auto sorting for a view-based forms

Form based on view – sorting by RecId is added automatically. It is better to remove it by adding sorting by another field

```csharp
View_ds.queryBuildDataSource().sortClear();
View _ds.queryBuildDataSource().addSortField(fieldNum(View, F1), SortOrder::Descending);
```