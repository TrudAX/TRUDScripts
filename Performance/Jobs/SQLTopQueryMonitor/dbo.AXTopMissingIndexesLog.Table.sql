/****** Object:  Table [dbo].[AXTopMissingIndexesLog]    Script Date: 7/8/2021 8:52:44 AM ******/
DROP TABLE IF EXISTS [dbo].[AXTopMissingIndexesLog]
GO
/****** Object:  Table [dbo].[AXTopMissingIndexesLog]    Script Date: 7/8/2021 8:52:44 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
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
	[user_scans] [bigint] NOT NULL
) ON [PRIMARY]
GO
