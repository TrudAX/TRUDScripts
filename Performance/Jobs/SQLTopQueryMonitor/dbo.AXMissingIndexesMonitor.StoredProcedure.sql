/****** Object:  StoredProcedure [dbo].[AXMissingIndexesMonitor]    Script Date: 26.07.2021 17:52:41 ******/
DROP PROCEDURE IF EXISTS [dbo].[AXMissingIndexesMonitor]
GO
/****** Object:  StoredProcedure [dbo].[AXMissingIndexesMonitor]    Script Date: 26.07.2021 17:52:41 ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER ON
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[AXMissingIndexesMonitor]') AND type in (N'P', N'PC'))
BEGIN
EXEC dbo.sp_executesql @statement = N'CREATE PROCEDURE [dbo].[AXMissingIndexesMonitor] AS' 
END
GO
--SELECT * FROM AXTopMissingIndexesLog
ALTER PROCEDURE [dbo].[AXMissingIndexesMonitor]
@DBName nvarchar(60) = 'AX63_WMS_PROD',
@SendEmailOperator nvarchar(60) = '',
@DisplayOnlyNewRecommendation int = 0,
@Debug int = 0
AS
BEGIN

	SET NOCOUNT ON;
	SET ANSI_NULLS OFF;

	DECLARE @DBID int = db_id(@DBName);

	DECLARE @NewMissingIndexesTbl TABLE 
	(	[tabname] [nvarchar](128) NULL,
		[DatabaseName] [nvarchar](128) NULL,
		[equality_columns] [nvarchar](4000) NULL,
		[inequality_columns] [nvarchar](4000) NULL,
		[avg_user_impact] numeric(18, 2) NULL,
		[included_columns] [nvarchar](4000) NULL,
		[user_seeks] [bigint] NOT NULL,
		[user_scans] [bigint] NOT NULL )

	INSERT INTO @NewMissingIndexesTbl

	SELECT TOP 50  object_name(d.object_id, d.database_id) as tabname, DB_NAME(database_id) AS DatabaseName, equality_columns, inequality_columns, avg_user_impact, included_columns,
	   user_seeks, user_scans
	FROM    sys.dm_db_missing_index_details d
	INNER JOIN sys.dm_db_missing_index_groups g
		ON    d.index_handle = g.index_handle
	INNER JOIN sys.dm_db_missing_index_group_stats s
		ON    g.index_group_handle = s.group_handle
	WHERE    database_id = @DBID
	ORDER BY  avg_total_user_cost * avg_user_impact *(user_seeks + user_scans) DESC 

	--Delete all less than 99
	DELETE @NewMissingIndexesTbl
		WHERE [avg_user_impact] < 99


	--Delete the previous recomendations
	IF (@DisplayOnlyNewRecommendation = 1)
	BEGIN
		DELETE FROM curLog
		from   @NewMissingIndexesTbl as curLog
		WHERE EXISTS (SELECT * FROM dbo.AXTopMissingIndexesLog prevLog
					  WHERE prevLog.[tabname]               = curLog.[tabname]
						AND prevLog.[DatabaseName]          = curLog.[DatabaseName]
						AND prevLog.[equality_columns]      = curLog.[equality_columns]
						AND COALESCE(prevLog.[inequality_columns], '')    = COALESCE(curLog.[inequality_columns], ''));
	END
	IF (@DisplayOnlyNewRecommendation = 0)
	BEGIN
		DELETE FROM curLog
		from   @NewMissingIndexesTbl as curLog
		WHERE EXISTS (SELECT * FROM dbo.AXTopMissingIndexesLog prevLog
					  WHERE prevLog.[tabname]               = curLog.[tabname]
						AND prevLog.[DatabaseName]          = curLog.[DatabaseName]
						AND prevLog.[equality_columns]      = curLog.[equality_columns]
						AND prevLog.IsApproved              = 1 
						AND COALESCE(prevLog.[inequality_columns], '')    = COALESCE(curLog.[inequality_columns], ''));
	END

	INSERT INTO [dbo].[AXTopMissingIndexesLog]
			   ([LogDateTime]
			   ,[tabname]
			   ,[DatabaseName]
			   ,[equality_columns]
			   ,[inequality_columns]
			   ,[avg_user_impact]
			   ,[included_columns]
			   ,[user_seeks]
			   ,[user_scans])
	   SELECT    GETDATE()
				,[tabname]
			   ,[DatabaseName]
			   ,[equality_columns]
			   ,[inequality_columns]
			   ,[avg_user_impact]
			   ,[included_columns]
			   ,[user_seeks]
			   ,[user_scans] FROM @NewMissingIndexesTbl

	SELECT * FROM @NewMissingIndexesTbl;


	--Send a notification

	DECLARE @NumOfRec INT
	SELECT @NumOfRec = count(*) FROM @NewMissingIndexesTbl

	IF @SendEmailOperator <> '' AND @NumOfRec > 0
	BEGIN
			DECLARE @Msg NVARCHAR(max)
			DECLARE @HTMLStr NVARCHAR(max)

			SET @Msg = N'AX Missing indexes alert';

			DECLARE @oper_email NVARCHAR(100)
			SET @oper_email = (SELECT email_address from msdb.dbo.sysoperators WHERE name = @SendEmailOperator)
			DECLARE @body NVARCHAR(MAX)
			SET     @body = N'<table>'
				+ N'<tr><th>TABLE</th><th>Database</th><th>Equality columns</th><th>Inequality_columns</th><th>Avg. impact</th><th>Included columns</th></tr>'
				+ CAST((
					SELECT [tabname]  AS td
						   ,[DatabaseName] AS td
						   ,[equality_columns] AS td
						   ,COALESCE([inequality_columns], '') AS td
						   ,[avg_user_impact] AS td
						   ,COALESCE([included_columns], '') AS td FROM @NewMissingIndexesTbl
						FOR XML RAW('tr'), ELEMENTS
				) AS NVARCHAR(MAX))
				+ N'</table>'

			SET @body = REPLACE(@body, '<tdc>', '<td class="center">');
			SET @body = REPLACE(@body, '</tdc>', '</td>');

			SET @HTMLStr = N'<html><body>' + @Msg + N'<br><br>' + @body + N'</body></html>';
			IF @Debug <> 0
				SELECT @HTMLStr  --DEBUG
			--SET @oper_email = 'trud81@gmail.com'  --DEBUG
			ELSE
				EXEC msdb.dbo.sp_send_dbmail  @profile_name = N'Main', @recipients = @oper_email, @subject = @Msg,  @body = @HTMLStr,  @body_format = 'HTML' ;
	END;
END

GO
