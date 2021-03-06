/****** Object:  StoredProcedure [dbo].[AXTopQueryMarkAsApproved]    Script Date: 5/23/2021 7:09:06 PM ******/
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[AXTopQueryMarkAsApproved]') AND type in (N'P', N'PC'))
DROP PROCEDURE [dbo].[AXTopQueryMarkAsApproved]
GO
/****** Object:  StoredProcedure [dbo].[AXTopQueryMarkAsApproved]    Script Date: 5/23/2021 7:09:06 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[AXTopQueryMarkAsApproved]
	@LogId INT,
	@ApprovedText nvarchar(128) = ''
AS
BEGIN
	SET NOCOUNT ON;

	declare @query_hash binary(8),  @query_plan_hash binary(8);

select 
    @query_hash = query_hash,
    @query_plan_hash = query_plan_hash
from dbo.AXTopQueryLog
where Id = @LogId;

IF @query_hash IS NOT NULL
BEGIN
	UPDATE dbo.AXTopQueryLogApproved
		SET IsApprovedQuery = 1, ApprovedText = @ApprovedText, ApprovedDate = GETDATE()
	WHERE query_hash = @query_hash AND query_plan_hash = @query_plan_hash;

	UPDATE dbo.AXTopQueryLog
		SET IsApprovedQuery = 1
	WHERE query_hash = @query_hash AND query_plan_hash = @query_plan_hash;
END
ELSE 
	BEGIN
	DECLARE @ErrorText nvarchar(30)
	SET @ErrorText = 'Log id ' + CAST(@LogId as nvarchar(10)) + ' doesnt exist';

	RAISERROR(@ErrorText, 16, 1);
	END
END
GO
