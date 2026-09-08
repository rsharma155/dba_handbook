SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

SELECT
    SchemaName = s.name,
    TableName = t.name,
    IndexName = i.name,
    IndexId = i.index_id,
    IndexType = i.type_desc,
    IsPrimaryKey = i.is_primary_key,
    IsUnique = i.is_unique,
    IsUniqueConstraint = i.is_unique_constraint,
    IsDisabled = i.is_disabled,
    FilterDefinition = i.filter_definition,
    KeyColumns =
    STUFF
    (
        (
            SELECT
                ', ' + QUOTENAME(c.name)
                + CASE
                    WHEN ic.is_descending_key = 1
                        THEN ' DESC'
                    ELSE ' ASC'
                  END
            FROM sys.index_columns ic
            INNER JOIN sys.columns c
                ON ic.object_id = c.object_id
               AND ic.column_id = c.column_id
            WHERE ic.object_id = i.object_id
              AND ic.index_id = i.index_id
              AND ic.is_included_column = 0
            ORDER BY ic.key_ordinal
            FOR XML PATH(''),TYPE
        ).value('.','nvarchar(max)')
    ,1,2,''),

    IncludedColumns =
    STUFF
    (
        (
            SELECT
                ', ' + QUOTENAME(c.name)
            FROM sys.index_columns ic
            INNER JOIN sys.columns c
                ON ic.object_id = c.object_id
               AND ic.column_id = c.column_id
            WHERE ic.object_id = i.object_id
              AND ic.index_id = i.index_id
              AND ic.is_included_column = 1
            ORDER BY c.column_id
            FOR XML PATH(''),TYPE
        ).value('.','nvarchar(max)')
    ,1,2,''),

    KeyColumnCount =
    (
        SELECT COUNT(*)
        FROM sys.index_columns ic
        WHERE ic.object_id = i.object_id
          AND ic.index_id = i.index_id
          AND ic.is_included_column = 0
    ),

    IncludedColumnCount =
    (
        SELECT COUNT(*)
        FROM sys.index_columns ic
        WHERE ic.object_id = i.object_id
          AND ic.index_id = i.index_id
          AND ic.is_included_column = 1
    )

FROM sys.tables t
INNER JOIN sys.schemas s
    ON t.schema_id = s.schema_id
INNER JOIN sys.indexes i
    ON t.object_id = i.object_id
WHERE i.index_id > 0
and t.name = 'dtrg_hos_AccBillDetail'
ORDER BY
    s.name,
    t.name,
    i.index_id;