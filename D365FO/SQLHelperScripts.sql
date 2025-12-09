-----------------------------------------------------------------------
-- Resolve enumvalue in a single SELECT
-----------------------------------------------------------------------
DECLARE @XppEnumLiteral NVARCHAR(200) = 'METSalesOrderProcessingStatus::OptimisationCompleted';
DECLARE @EnumValue      INT;
DECLARE @ErrorMessage   NVARCHAR(4000);

SELECT @EnumValue = ev.enumvalue
FROM   ENUMVALUETABLE ev
JOIN   ENUMIDTABLE   ei ON ei.ID = ev.enumid
WHERE  ei.NAME = LEFT(@XppEnumLiteral, CHARINDEX('::', @XppEnumLiteral) - 1)
  AND  ev.NAME = SUBSTRING(
                        @XppEnumLiteral,
                        CHARINDEX('::', @XppEnumLiteral) + 2,
                        LEN(@XppEnumLiteral)
                  );

IF @EnumValue IS NULL
BEGIN
    SET @ErrorMessage = 'ERROR: Enum literal "' 
                        + @XppEnumLiteral 
                        + '" could not be resolved in ENUMIDTABLE/ENUMVALUETABLE.';

    THROW 51000, @ErrorMessage, 1;
END;

PRINT 'Resolved EnumValue = ' + CAST(@EnumValue AS NVARCHAR(20));


-----------------------------------------------------------------------
-- Find All Fields With No DataEntities Via CrossRef
-----------------------------------------------------------------------

SELECT
    -- Extract the text between the first and second slash for the TableName
    SUBSTRING(Path, CHARINDEX('/', Path) + 1, CHARINDEX('/', Path, CHARINDEX('/', Path) + 1) - CHARINDEX('/', Path) - 1) AS TableName,
    -- Extract the text after the second slash for the FieldPath
    SUBSTRING(Path, CHARINDEX('/', Path, CHARINDEX('/', Path) + 1) + 1, LEN(Path)) AS FieldPath,
    N.*
FROM [dbo].[Names] N
WHERE N.ProviderId = 1
  AND N.ModuleId In (select Id from Modules where Module = 'AAModuleToSearch')
  AND (N.Path LIKE 'Table/%TableField%' OR N.Path LIKE 'TableExtension/%TableField%')
  AND N.Path NOT LIKE 'Table/%TableFieldGroup%'
  AND N.Path NOT LIKE '%?%'
  AND NOT EXISTS (
    SELECT 1
    FROM [dbo].[References] R
    INNER JOIN [dbo].[Names] NSource ON R.SourceId = NSource.Id
    WHERE R.TargetId = N.Id
      AND NSource.Path  LIKE 'DataEntityView/%DataEntityViewMappedField%'
  )
  AND NOT (
    RIGHT(SUBSTRING(Path, CHARINDEX('/', Path) + 1, CHARINDEX('/', Path, CHARINDEX('/', Path) + 1) - CHARINDEX('/', Path) - 1), 7) = 'Staging'
    OR RIGHT(SUBSTRING(Path, CHARINDEX('/', Path) + 1, CHARINDEX('/', Path, CHARINDEX('/', Path) + 1) - CHARINDEX('/', Path) - 1), 3) = 'Tmp'
  )
  ORDER BY TableName, FieldPath
