--akaz, 06.10.2014, v1.1
--depa, 06.04.2015, v1.2
use [work]
go
declare @time_format	varchar(20)	= 'H:mm:ss';
declare @date_locale	varchar(5)	= 'ru-ru';
declare @date_null		datetime	= {d '1901-01-01'};

WITH DM_EXEC_SESSION_PARSE (session_id, ax_user, ax_s)
AS (
SELECT
	session_id,
	SUBSTRING(CAST(ss.CONTEXT_INFO as varchar(128)), 2, PATINDEX('% %',
		LTRIM(CAST(ss.CONTEXT_INFO as varchar(128))))) as ax_user,
	CAST(SUBSTRING(LTRIM(CAST(ss.CONTEXT_INFO as varchar(128))),
		PATINDEX('% %', LTRIM(CAST(ss.CONTEXT_INFO as varchar(128)))) + 1,
		PATINDEX('% %', SUBSTRING(LTRIM(CAST(ss.CONTEXT_INFO as varchar(128))),
		PATINDEX('% %', LTRIM(CAST(ss.CONTEXT_INFO as varchar(128)))) + 1,
		LEN(CAST(ss.CONTEXT_INFO as varchar(128))))) - 1) as int) as ax_s
FROM	sys.dm_exec_sessions ss
WHERE	program_name in ('Microsoft Dynamics AX')
	AND	CAST(CONTEXT_INFO as varchar(128)) > ''
),
DM_EXEC_SESSION_FILTER (session_id, database_id, status)
AS (
	SELECT DISTINCT s.session_id, s.database_id, s.status
	FROM	sys.dm_exec_sessions s
	JOIN	sys.dm_exec_requests r
		ON	(s.session_id = r.session_id AND r.sql_handle IS NOT NULL AND r.plan_handle IS NOT NULL)
		OR	(s.session_id = r.blocking_session_id)
)
SELECT ss.session_id AS [spid]
	,COALESCE(r.blocking_session_id, 0) AS [blck]
	,FORMAT(dateadd(MILLISECOND, COALESCE(r.wait_time, 0), @date_null), @time_format) AS [wait_time]
	,COALESCE(r.wait_type, '') AS [wait_type]
	,COALESCE(r.command, '') AS [command]
	,ss.status as [status]
	,COALESCE(bb.caption, '') AS [batch_caption]
	,COALESCE(FORMAT(dateadd(second, datediff(s, r.start_time, GetDate()), @date_null), @time_format), '') AS [running_time]
	,COALESCE((SELECT TOP 1 name FROM sys.databases WHERE database_id = ss.database_id), '') as [db_name]
	,COALESCE(ss_ctx.ax_user, '') AS [ax_user]
	,COALESCE(ss_ctx.ax_s, '') AS [ax_s]
	,sp.hostname AS [host_name]
	,sp.hostprocess AS [host_pid]
	,sp.loginame AS [login_name]
	,FORMAT(sp.login_time, 'G', @date_locale) AS [login_time]
	,CASE WHEN r.plan_handle IS NOT NULL THEN COALESCE((SELECT TOP 1 query_plan	FROM sys.dm_exec_query_plan(r.plan_handle)), '') ELSE '' END AS [query_plan]
	,CASE WHEN r.sql_handle  IS NOT NULL THEN COALESCE((SELECT TOP 1 text		FROM sys.dm_exec_sql_text(r.sql_handle)), '') ELSE '' END AS [query]
	,COALESCE(FORMAT(r.start_time, 'G', @date_locale), '') as [start_time]
	,COALESCE(r.percent_complete, 0) AS [cmplt_pct]
	,COALESCE(FORMAT(dateadd(MILLISECOND, r.estimated_completion_time, @date_null),		@time_format), '') AS [est_time_lft]
	,COALESCE(FORMAT(dateadd(MILLISECOND, r.estimated_completion_time, GetDate()), 'G',	@date_locale), '') AS [est_compl_time]
FROM		DM_EXEC_SESSION_FILTER	ss
JOIN		sys.sysprocesses		sp
	ON	ss.session_id = sp.spid
LEFT JOIN	sys.dm_exec_requests	r
	ON	ss.session_id = r.session_id
LEFT JOIN	DM_EXEC_SESSION_PARSE	ss_ctx
    ON	ss_ctx.session_id = ss.session_id
LEFT JOIN	[dbo].[BATCH]			bb
	ON	bb.SESSIONIDX = ss_ctx.ax_s
    AND	bb.STATUS = 2
WHERE	ss.session_id <> @@SPID
ORDER BY ss.session_id