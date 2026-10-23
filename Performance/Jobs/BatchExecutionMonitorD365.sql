-- Batch Job Analyzer - SIMPLE mode
DECLARE @MinDurationMin decimal(12, 1) = 0.1;   -- hide jobs running less than this many minutes; NULL = show all

SELECT
    bj.RECID                                                                  AS BatchJobId,
    bj.CAPTION                                                                AS BatchJobName,
    bj.COMPANY                                                                AS Company,
    bj.BATCHGROUP                                                             AS BatchGroup,
    bj.STARTDATETIME                                                          AS StartedUtc,
    CASE WHEN bj.STARTDATETIME > '1901-01-01'
         THEN CAST(DATEDIFF_BIG(SECOND, bj.STARTDATETIME, GETUTCDATE()) / 60.0 AS decimal(12, 1)) END AS CurrentDurationMin,
    t.TotalTasks, t.Executing, t.Waiting, t.Ready, t.Ended, t.Error, t.Hold, t.NotRun, t.Cancelled,
    CASE WHEN t.RetriedTasks > 0 THEN 'Yes' ELSE 'No' END                     AS Retried,
    t.RetriedTasks, t.MaxRetryCount,
    ISNULL(lr.LastRunResult, 'No previous run')                               AS LastRunResult,
    lr.LastRunStartUtc, lr.LastRunEndUtc, lr.LastRunDurationMin
FROM BATCHJOB bj
OUTER APPLY (
    SELECT COUNT(*)                                          AS TotalTasks,
           SUM(CASE WHEN b.STATUS = 2      THEN 1 ELSE 0 END) AS Executing,
           SUM(CASE WHEN b.STATUS = 1      THEN 1 ELSE 0 END) AS Waiting,
           SUM(CASE WHEN b.STATUS = 5      THEN 1 ELSE 0 END) AS Ready,
           SUM(CASE WHEN b.STATUS = 4      THEN 1 ELSE 0 END) AS Ended,
           SUM(CASE WHEN b.STATUS = 3      THEN 1 ELSE 0 END) AS Error,
           SUM(CASE WHEN b.STATUS = 0      THEN 1 ELSE 0 END) AS Hold,
           SUM(CASE WHEN b.STATUS = 6      THEN 1 ELSE 0 END) AS NotRun,
           SUM(CASE WHEN b.STATUS IN (7, 8) THEN 1 ELSE 0 END) AS Cancelled,
           SUM(CASE WHEN b.RETRYCOUNT > 0  THEN 1 ELSE 0 END) AS RetriedTasks,
           MAX(b.RETRYCOUNT)                                 AS MaxRetryCount
    FROM BATCH b
    WHERE b.BATCHJOBID = bj.RECID
) t
OUTER APPLY (
    -- history row is written when a run ends, so the newest one is the previous run
    SELECT TOP 1
           CASE h.STATUS
               WHEN 0 THEN 'Hold' WHEN 1 THEN 'Waiting' WHEN 2 THEN 'Executing'
               WHEN 3 THEN 'Error' WHEN 4 THEN 'Ended' WHEN 5 THEN 'Ready'
               WHEN 6 THEN 'NotRun' WHEN 7 THEN 'Cancelling' WHEN 8 THEN 'Canceled'
               WHEN 9 THEN 'Scheduled' ELSE 'Unknown(' + CAST(h.STATUS AS varchar(10)) + ')'
           END                                                                     AS LastRunResult,
           h.STARTDATETIME                                                         AS LastRunStartUtc,
           h.ENDDATETIME                                                           AS LastRunEndUtc,
           CASE WHEN h.STARTDATETIME > '1901-01-01' AND h.ENDDATETIME > '1901-01-01'
                THEN CAST(DATEDIFF_BIG(SECOND, h.STARTDATETIME, h.ENDDATETIME) / 60.0 AS decimal(12, 1)) END AS LastRunDurationMin
    FROM BATCHJOBHISTORY h
    WHERE h.BATCHJOBID = bj.RECID
    ORDER BY h.RECID DESC
) lr
WHERE bj.STATUS = 2
  AND (@MinDurationMin IS NULL
       OR bj.STARTDATETIME <= '1901-01-01'
       OR DATEDIFF_BIG(SECOND, bj.STARTDATETIME, GETUTCDATE()) / 60.0 >= @MinDurationMin)
ORDER BY CurrentDurationMin DESC;



-- Batch Job Analyzer - ENHANCED mode
SET NOCOUNT ON;

DECLARE @SampleSeconds int = 20;
DECLARE @MinDurationMin decimal(12, 1) = 0.1;   -- hide jobs running less than this many minutes; NULL = show all
DECLARE @Delay char(8) = CONVERT(char(8), DATEADD(SECOND, @SampleSeconds, 0), 108);

IF OBJECT_ID('tempdb..#Snap') IS NOT NULL DROP TABLE #Snap;
CREATE TABLE #Snap (
    SnapNo int, SnapTime datetime2, session_id int, login_time datetime, AxSessionId int,
    LogicalReads bigint, CpuMs bigint, Writes bigint, PhysicalReads bigint
);

DECLARE @i int = 1;
WHILE @i <= 2
BEGIN
    IF @i = 2 WAITFOR DELAY @Delay;

    INSERT INTO #Snap
    SELECT @i, SYSDATETIME(), s.session_id, s.login_time, TRY_CAST(axSessionId.value AS int),
           s.logical_reads + ISNULL(r.logical_reads, 0),
           s.cpu_time      + ISNULL(r.cpu_time, 0),
           s.writes        + ISNULL(r.writes, 0),
           s.reads         + ISNULL(r.reads, 0)
    FROM sys.dm_exec_sessions s
    OUTER APPLY (SELECT SUM(rq.logical_reads) AS logical_reads, SUM(rq.cpu_time) AS cpu_time,
                        SUM(rq.writes) AS writes, SUM(rq.reads) AS reads
                 FROM sys.dm_exec_requests rq WHERE rq.session_id = s.session_id) r
    -- context_info: '[<ts> | <ts> ++ ]{AxUser} {AxSessionId} CLIENT ...' -> token right before ' CLIENT'
    CROSS APPLY (SELECT LTRIM(RTRIM(CONVERT(varchar(128), s.context_info))) AS ctx) rawctx
    CROSS APPLY (SELECT CHARINDEX(' CLIENT', rawctx.ctx) AS pos) clientMarker
    CROSS APPLY (SELECT CASE WHEN clientMarker.pos > 0 THEN LEFT(rawctx.ctx, clientMarker.pos - 1) END AS beforeClient) bc
    CROSS APPLY (SELECT CHARINDEX(' ', REVERSE(ISNULL(bc.beforeClient, ''))) AS revPos) lastSp
    CROSS APPLY (SELECT CASE WHEN lastSp.revPos > 0 THEN RIGHT(bc.beforeClient, lastSp.revPos - 1) ELSE bc.beforeClient END AS value) axSessionId
    WHERE s.is_user_process = 1 AND s.session_id <> @@SPID;

    SET @i += 1;
END;

-- Per-spid load in the sample window, mapped to the batch task it currently belongs to
IF OBJECT_ID('tempdb..#SpidLoad') IS NOT NULL DROP TABLE #SpidLoad;
SELECT s2.session_id, b.BATCHJOBID, b.RECID AS BatchTaskId,
       d.LogicalReads, d.CpuMs, d.Writes, d.PhysicalReads
INTO #SpidLoad
FROM #Snap s2
LEFT JOIN #Snap s1 ON s1.SnapNo = 1 AND s1.session_id = s2.session_id
-- Reset only when the counters actually dropped (or the spid re-logged in). An owner change alone is NOT a reset:
-- if the AOS reuses a connection without resetting it, using the snapshot-2 value would credit the new owner with
-- the connection's whole lifetime of reads (seen in tier 2: a 1-min job out-ranking a 175-min job).
CROSS APPLY (SELECT CASE WHEN s1.session_id IS NOT NULL
                          AND s1.login_time = s2.login_time
                          AND s2.LogicalReads >= s1.LogicalReads AND s2.CpuMs >= s1.CpuMs AND s2.Writes >= s1.Writes
                         THEN 1 ELSE 0 END AS IsContinuous) c
CROSS APPLY (SELECT CASE WHEN c.IsContinuous = 1 THEN s2.LogicalReads  - s1.LogicalReads  ELSE s2.LogicalReads  END AS LogicalReads,
                    CASE WHEN c.IsContinuous = 1 THEN s2.CpuMs         - s1.CpuMs         ELSE s2.CpuMs         END AS CpuMs,
                    CASE WHEN c.IsContinuous = 1 THEN s2.Writes        - s1.Writes        ELSE s2.Writes        END AS Writes,
                    CASE WHEN c.IsContinuous = 1 THEN s2.PhysicalReads - s1.PhysicalReads ELSE s2.PhysicalReads END AS PhysicalReads) d
LEFT JOIN SYSCLIENTSESSIONS ccs ON ccs.SESSIONID = s2.AxSessionId
LEFT JOIN SYSSERVERSESSIONS sss ON sss.SERVERID = ccs.SERVERID
LEFT JOIN BATCH b ON b.SESSIONIDX = ccs.SESSIONID
                 AND b.SESSIONLOGINDATETIME = ccs.LOGINDATETIME
                 AND b.STATUS = 2
                 AND RIGHT(b.SERVERID, LEN(b.SERVERID) - CHARINDEX(':', b.SERVERID))
                   = RIGHT(sss.AOSID, LEN(sss.AOSID) - CHARINDEX(':', sss.AOSID))
WHERE s2.SnapNo = 2;

DECLARE @ActualSampleSec decimal(10, 1) =
    (SELECT DATEDIFF(MILLISECOND, MIN(SnapTime), MAX(SnapTime)) / 1000.0 FROM (SELECT SnapNo, MIN(SnapTime) AS SnapTime FROM #Snap GROUP BY SnapNo) x);
DECLARE @TotalReads bigint = (SELECT SUM(LogicalReads) FROM #SpidLoad);

-- Blocking right now (after the sample), with the waited-on table resolved
IF OBJECT_ID('tempdb..#Blk') IS NOT NULL DROP TABLE #Blk;
SELECT r.session_id AS BlockedSpid, r.blocking_session_id AS BlockingSpid, r.wait_time, res.WaitTable
INTO #Blk
FROM sys.dm_exec_requests r
CROSS APPLY (SELECT CHARINDEX(':', r.wait_resource) AS c1) p1
CROSS APPLY (SELECT CASE WHEN p1.c1 > 0 THEN LEFT(r.wait_resource, p1.c1 - 1) END AS rt,
                    CASE WHEN p1.c1 > 0 THEN LTRIM(SUBSTRING(r.wait_resource, p1.c1 + 1, 512)) ELSE '' END AS afterType) p2
CROSS APPLY (SELECT CHARINDEX(':', p2.afterType) AS c2) p3
CROSS APPLY (SELECT CASE WHEN p3.c2 > 0 THEN SUBSTRING(p2.afterType, p3.c2 + 1, 512) ELSE '' END AS afterDb) p4
CROSS APPLY (SELECT TRY_CAST(LEFT(p4.afterDb, PATINDEX('%[^0-9]%', p4.afterDb + ' ') - 1) AS bigint) AS resId) p5
CROSS APPLY (SELECT CASE p2.rt
                        WHEN 'KEY'    THEN (SELECT TOP 1 OBJECT_NAME(pt.object_id) FROM sys.partitions pt WHERE pt.hobt_id = p5.resId)
                        WHEN 'OBJECT' THEN OBJECT_NAME(CAST(p5.resId AS int))
                        ELSE p2.rt
                    END AS WaitTable) res
WHERE r.blocking_session_id > 0;

SELECT
    bj.RECID                                                                  AS BatchJobId,
    bj.CAPTION                                                                AS BatchJobName,
    bj.COMPANY                                                                AS Company,
    bj.BATCHGROUP                                                             AS BatchGroup,
    bj.STARTDATETIME                                                          AS StartedUtc,
    CASE WHEN bj.STARTDATETIME > '1901-01-01'
         THEN CAST(DATEDIFF_BIG(SECOND, bj.STARTDATETIME, GETUTCDATE()) / 60.0 AS decimal(12, 1)) END AS CurrentDurationMin,
    t.TotalTasks, t.Executing, t.Waiting, t.Ready, t.Ended, t.Error, t.Hold, t.NotRun, t.Cancelled,
    CASE WHEN t.RetriedTasks > 0 THEN 'Yes' ELSE 'No' END                     AS Retried,
    t.RetriedTasks, t.MaxRetryCount,
    ISNULL(lr.LastRunResult, 'No previous run')                               AS LastRunResult,
    lr.LastRunStartUtc, lr.LastRunEndUtc, lr.LastRunDurationMin,
    -- enhanced: SQL load in the sample window
    @ActualSampleSec                                                          AS SampleSec,
    ISNULL(ld.SqlSessions, 0)                                                 AS SqlSessions,
    ISNULL(ld.LogicalReads, 0)                                                AS LogicalReads,
    CAST(ISNULL(ld.LogicalReads, 0) / NULLIF(@ActualSampleSec, 0) AS decimal(18, 0)) AS LogicalReadsPerSec,
    CAST(100.0 * ISNULL(ld.LogicalReads, 0) / NULLIF(@TotalReads, 0) AS decimal(5, 1)) AS PctOfAllSqlReads,
    ISNULL(ld.CpuMs, 0)                                                       AS CpuMs,
    ISNULL(ld.PhysicalReads, 0)                                               AS PhysicalReads,
    ISNULL(ld.Writes, 0)                                                      AS Writes,
    -- enhanced: blocking
    CASE WHEN bd.BlockedSpids IS NOT NULL THEN 'Yes' ELSE 'No' END            AS IsBlocked,
    bd.BlockedSpids, bd.BlockedOn, bd.BlockedBySpids, bd.MaxWaitSec,
    CASE WHEN bg.BlockingSpids IS NOT NULL THEN 'Yes' ELSE 'No' END           AS IsBlocking,
    bg.BlockingSpids, bg.VictimSpids
FROM BATCHJOB bj
OUTER APPLY (
    SELECT COUNT(*)                                          AS TotalTasks,
           SUM(CASE WHEN b.STATUS = 2      THEN 1 ELSE 0 END) AS Executing,
           SUM(CASE WHEN b.STATUS = 1      THEN 1 ELSE 0 END) AS Waiting,
           SUM(CASE WHEN b.STATUS = 5      THEN 1 ELSE 0 END) AS Ready,
           SUM(CASE WHEN b.STATUS = 4      THEN 1 ELSE 0 END) AS Ended,
           SUM(CASE WHEN b.STATUS = 3      THEN 1 ELSE 0 END) AS Error,
           SUM(CASE WHEN b.STATUS = 0      THEN 1 ELSE 0 END) AS Hold,
           SUM(CASE WHEN b.STATUS = 6      THEN 1 ELSE 0 END) AS NotRun,
           SUM(CASE WHEN b.STATUS IN (7, 8) THEN 1 ELSE 0 END) AS Cancelled,
           SUM(CASE WHEN b.RETRYCOUNT > 0  THEN 1 ELSE 0 END) AS RetriedTasks,
           MAX(b.RETRYCOUNT)                                 AS MaxRetryCount
    FROM BATCH b
    WHERE b.BATCHJOBID = bj.RECID
) t
OUTER APPLY (
    SELECT TOP 1
           CASE h.STATUS
               WHEN 0 THEN 'Hold' WHEN 1 THEN 'Waiting' WHEN 2 THEN 'Executing'
               WHEN 3 THEN 'Error' WHEN 4 THEN 'Ended' WHEN 5 THEN 'Ready'
               WHEN 6 THEN 'NotRun' WHEN 7 THEN 'Cancelling' WHEN 8 THEN 'Canceled'
               WHEN 9 THEN 'Scheduled' ELSE 'Unknown(' + CAST(h.STATUS AS varchar(10)) + ')'
           END                                                                     AS LastRunResult,
           h.STARTDATETIME                                                         AS LastRunStartUtc,
           h.ENDDATETIME                                                           AS LastRunEndUtc,
           CASE WHEN h.STARTDATETIME > '1901-01-01' AND h.ENDDATETIME > '1901-01-01'
                THEN CAST(DATEDIFF_BIG(SECOND, h.STARTDATETIME, h.ENDDATETIME) / 60.0 AS decimal(12, 1)) END AS LastRunDurationMin
    FROM BATCHJOBHISTORY h
    WHERE h.BATCHJOBID = bj.RECID
    ORDER BY h.RECID DESC
) lr
OUTER APPLY (
    SELECT COUNT(*) AS SqlSessions, SUM(sl.LogicalReads) AS LogicalReads, SUM(sl.CpuMs) AS CpuMs,
           SUM(sl.Writes) AS Writes, SUM(sl.PhysicalReads) AS PhysicalReads
    FROM #SpidLoad sl WHERE sl.BATCHJOBID = bj.RECID
) ld
OUTER APPLY (
    -- this job's spids that are waiting on someone else
    SELECT STRING_AGG(CAST(k.BlockedSpid AS varchar(10)), ', ')  AS BlockedSpids,
           STRING_AGG(ISNULL(k.WaitTable, '?'), ', ')            AS BlockedOn,
           STRING_AGG(CAST(k.BlockingSpid AS varchar(10)) + ' (' + ISNULL(bjb.CAPTION, 'Non-batch') + ')', ', ') AS BlockedBySpids,
           MAX(k.wait_time) / 1000                               AS MaxWaitSec
    FROM #Blk k
    JOIN #SpidLoad me ON me.session_id = k.BlockedSpid AND me.BATCHJOBID = bj.RECID
    LEFT JOIN #SpidLoad oth ON oth.session_id = k.BlockingSpid
    LEFT JOIN BATCHJOB bjb ON bjb.RECID = oth.BATCHJOBID
) bd
OUTER APPLY (
    -- this job's spids that are blocking others
    SELECT STRING_AGG(CAST(x.BlockingSpid AS varchar(10)), ', ') AS BlockingSpids,
           SUM(x.Victims)                                        AS VictimSpids
    FROM (SELECT k.BlockingSpid, COUNT(*) AS Victims
          FROM #Blk k JOIN #SpidLoad me ON me.session_id = k.BlockingSpid AND me.BATCHJOBID = bj.RECID
          GROUP BY k.BlockingSpid) x
) bg
WHERE bj.STATUS = 2
  AND (@MinDurationMin IS NULL
       OR bj.STARTDATETIME <= '1901-01-01'
       OR DATEDIFF_BIG(SECOND, bj.STARTDATETIME, GETUTCDATE()) / 60.0 >= @MinDurationMin)
ORDER BY ISNULL(ld.LogicalReads, 0) DESC, CurrentDurationMin DESC;
-- Keep this SELECT as the LAST statement: anything after it leaves the ODBC connection busy when run from D365FO
-- ("Connection is busy with results for another command"). Temp tables are dropped at the start of the next run / on connection reset.
