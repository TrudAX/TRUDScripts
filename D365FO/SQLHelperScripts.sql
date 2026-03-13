-----------------------------------------------------------------------
-- Resolve enumvalue in a single SELECT
-----------------------------------------------------------------------
DECLARE @XppEnumLiteral NVARCHAR(200) = 'SalesOrderProcessingStatus::OptimisationCompleted';
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


-- Target enum name
DECLARE @EnumName NVARCHAR(200) = 'SalesOrderProcessingStatus';

-- Return all elements for this enum
SELECT
      ev.NAME          AS EnumElementName,
      ev.ENUMVALUE     AS EnumValue
FROM   ENUMVALUETABLE ev
JOIN   ENUMIDTABLE   ei ON ei.ID = ev.ENUMID
WHERE  ei.NAME = @EnumName
ORDER BY ev.ENUMVALUE;

-----------------------------------------------------------------------
-- Find All Fields With No DataEntities Via CrossRef
-----------------------------------------------------------------------

WITH SlashPositions AS (
    SELECT
        N.*,
        CHARINDEX('/', N.Path)                                             AS Slash1,
        CHARINDEX('/', N.Path, CHARINDEX('/', N.Path) + 1)                AS Slash2
    FROM [dbo].[Names] N
    WHERE N.ProviderId = 2   -- corrected from 1; Table/TableField rows use ProviderId 2
      AND N.ModuleId IN (SELECT Id FROM [dbo].[Modules] WHERE Module = 'YOUMODULENAME')
      AND (N.Path LIKE 'Table/%TableField%' OR N.Path LIKE 'TableExtension/%TableField%')
      AND N.Path NOT LIKE 'Table/%TableFieldGroup%'
      AND N.Path NOT LIKE '%?%'
)
SELECT
    -- NULLIF(Slash2, 0) prevents a negative length when no second slash exists
    SUBSTRING(Path, Slash1 + 1, NULLIF(Slash2, 0) - Slash1 - 1)   AS TableName,
    CASE WHEN Slash2 > 0
         THEN SUBSTRING(Path, Slash2 + 1, LEN(Path))
         ELSE NULL
    END                                                             AS FieldPath,
    Id, Path, ProviderId, ModuleId
FROM SlashPositions
WHERE NOT EXISTS (
    SELECT 1
    FROM [dbo].[References] R
    INNER JOIN [dbo].[Names] NSource ON R.SourceId = NSource.Id
    WHERE R.TargetId = SlashPositions.Id
      AND NSource.Path LIKE 'DataEntityView/%DataEntityViewMappedField%'
)
AND NOT (
    RIGHT(SUBSTRING(Path, Slash1 + 1, NULLIF(Slash2, 0) - Slash1 - 1), 7) = 'Staging'
    OR RIGHT(SUBSTRING(Path, Slash1 + 1, NULLIF(Slash2, 0) - Slash1 - 1), 3) = 'Tmp'
)
ORDER BY TableName, FieldPath;
