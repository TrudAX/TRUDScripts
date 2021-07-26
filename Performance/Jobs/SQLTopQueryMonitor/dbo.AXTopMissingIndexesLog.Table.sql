IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[AXTopMissingIndexesLog]') AND type in (N'U'))
ALTER TABLE [dbo].[AXTopMissingIndexesLog] DROP CONSTRAINT IF EXISTS [DF_AXTopMissingIndexesLog_ApprovedText]
GO
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[AXTopMissingIndexesLog]') AND type in (N'U'))
ALTER TABLE [dbo].[AXTopMissingIndexesLog] DROP CONSTRAINT IF EXISTS [DF_AXTopMissingIndexesLog_IsApproved]
GO
/****** Object:  Table [dbo].[AXTopMissingIndexesLog]    Script Date: 26.07.2021 17:52:41 ******/
DROP TABLE IF EXISTS [dbo].[AXTopMissingIndexesLog]
GO
/****** Object:  Table [dbo].[AXTopMissingIndexesLog]    Script Date: 26.07.2021 17:52:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[AXTopMissingIndexesLog]') AND type in (N'U'))
BEGIN
CREATE TABLE [dbo].[AXTopMissingIndexesLog](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[LogDateTime] [datetime] NOT NULL,
	[tabname] [nvarchar](128) NULL,
	[DatabaseName] [nvarchar](128) NULL,
	[equality_columns] [nvarchar](4000) NULL,
	[inequality_columns] [nvarchar](4000) NULL,
	[avg_user_impact] [numeric](18, 2) NULL,
	[included_columns] [nvarchar](4000) NULL,
	[user_seeks] [bigint] NOT NULL,
	[user_scans] [bigint] NOT NULL,
	[IsApproved] [bit] NOT NULL,
	[ApprovedText] [nvarchar](50) NOT NULL
) ON [PRIMARY]
END
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[DF_AXTopMissingIndexesLog_IsApproved]') AND type = 'D')
BEGIN
ALTER TABLE [dbo].[AXTopMissingIndexesLog] ADD  CONSTRAINT [DF_AXTopMissingIndexesLog_IsApproved]  DEFAULT ((0)) FOR [IsApproved]
END

GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[DF_AXTopMissingIndexesLog_ApprovedText]') AND type = 'D')
BEGIN
ALTER TABLE [dbo].[AXTopMissingIndexesLog] ADD  CONSTRAINT [DF_AXTopMissingIndexesLog_ApprovedText]  DEFAULT ('') FOR [ApprovedText]
END

GO
