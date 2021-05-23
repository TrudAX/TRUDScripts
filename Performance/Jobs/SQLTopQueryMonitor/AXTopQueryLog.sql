/****** Object:  Table [dbo].[AXTopQueryLog]    Script Date: 5/23/2021 9:45:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[AXTopQueryLog](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[LogDateTime] [datetime] NOT NULL,
	[DataBase] [nvarchar](128) NOT NULL,
	[TEXT] [nvarchar](max) NOT NULL,
	[execution_count] [bigint] NOT NULL,
	[last_elapsed_time_in_mS] [bigint] NOT NULL,
	[total_logical_reads] [bigint] NOT NULL,
	[last_logical_reads] [bigint] NOT NULL,
	[total_logical_writes] [bigint] NOT NULL,
	[last_logical_writes] [bigint] NOT NULL,
	[last_physical_reads] [bigint] NOT NULL,
	[total_physical_reads] [bigint] NOT NULL,
	[total_worker_time_in_S] [bigint] NOT NULL,
	[last_worker_time_in_mS] [bigint] NOT NULL,
	[total_elapsed_time_in_S] [bigint] NOT NULL,
	[last_execution_time] [datetime] NOT NULL,
	[Age of the Plan(Minutes)] [int] NOT NULL,
	[Has 99%] [varchar](7) NOT NULL,
	[query_plan] [xml] NOT NULL,
	[query_hash] [binary](8) NOT NULL,
	[query_plan_hash] [binary](8) NOT NULL,
	[IsApprovedQuery] [int] NOT NULL,
 CONSTRAINT [PK_AXTopQueryLog] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

ALTER TABLE [dbo].[AXTopQueryLog] ADD  CONSTRAINT [DF_AXTopQueryLog_IsApprovedQuery]  DEFAULT ((0)) FOR [IsApprovedQuery]
GO

