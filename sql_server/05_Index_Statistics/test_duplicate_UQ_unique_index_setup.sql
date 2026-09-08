/*
================================================================================
Test harness for duplicate_UQ_unique_index_details.sql
================================================================================
Creates 10 tables with intentional duplicate / overlapping UNIQUE indexes,
UNIQUE constraints, PRIMARY KEY overlaps, and non-unique duplicates of unique
keys so you can validate the diagnostic script locally.

Usage:
    1. USE your test database.
    2. Run this script (safe to re-run: drops objects first).
    3. Run duplicate_UQ_unique_index_details.sql with @DatabaseList = that DB.
    4. Compare results to the "Expected findings" comments below each table.

Cleanup:
    Re-run this script, or execute the DROP block at the bottom alone.
================================================================================
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

/*------------------------------------------------------------------------------
  Cleanup (re-runnable)
------------------------------------------------------------------------------*/
IF OBJECT_ID(N'dbo.UQ_Test_10_FilteredUnique', N'U') IS NOT NULL DROP TABLE dbo.UQ_Test_10_FilteredUnique;
IF OBJECT_ID(N'dbo.UQ_Test_09_IncludesDiffer', N'U') IS NOT NULL DROP TABLE dbo.UQ_Test_09_IncludesDiffer;
IF OBJECT_ID(N'dbo.UQ_Test_08_UniqueVsNonUniquePrefix', N'U') IS NOT NULL DROP TABLE dbo.UQ_Test_08_UniqueVsNonUniquePrefix;
IF OBJECT_ID(N'dbo.UQ_Test_07_TwoUniqueLeftPrefix', N'U') IS NOT NULL DROP TABLE dbo.UQ_Test_07_TwoUniqueLeftPrefix;
IF OBJECT_ID(N'dbo.UQ_Test_06_UniqueKeyOrderDiffers', N'U') IS NOT NULL DROP TABLE dbo.UQ_Test_06_UniqueKeyOrderDiffers;
IF OBJECT_ID(N'dbo.UQ_Test_05_UniqueVsNonUniqueSameKey', N'U') IS NOT NULL DROP TABLE dbo.UQ_Test_05_UniqueVsNonUniqueSameKey;
IF OBJECT_ID(N'dbo.UQ_Test_04_UniqueDuplicatesPK', N'U') IS NOT NULL DROP TABLE dbo.UQ_Test_04_UniqueDuplicatesPK;
IF OBJECT_ID(N'dbo.UQ_Test_03_UC_vs_UniqueIndex', N'U') IS NOT NULL DROP TABLE dbo.UQ_Test_03_UC_vs_UniqueIndex;
IF OBJECT_ID(N'dbo.UQ_Test_02_ExactDupUniqueIndexes', N'U') IS NOT NULL DROP TABLE dbo.UQ_Test_02_ExactDupUniqueIndexes;
IF OBJECT_ID(N'dbo.UQ_Test_01_ExactDupUC_and_Unique', N'U') IS NOT NULL DROP TABLE dbo.UQ_Test_01_ExactDupUC_and_Unique;

PRINT N'Dropped existing UQ_Test_* tables (if any).';
GO

/*==============================================================================
  Table 01 — UNIQUE constraint + identical unique index (same key, includes)
  Expected: EXACT_DUPLICATE or DUPLICATE_KEY
            Keep: UQ constraint  Drop: IX_UQ_Test_01_Code_Dup
==============================================================================*/
CREATE TABLE dbo.UQ_Test_01_ExactDupUC_and_Unique
(
    Id   INT           NOT NULL CONSTRAINT PK_UQ_Test_01 PRIMARY KEY,
    Code NVARCHAR(50)  NOT NULL,
    Name NVARCHAR(100) NULL
);

ALTER TABLE dbo.UQ_Test_01_ExactDupUC_and_Unique
    ADD CONSTRAINT UQ_Test_01_Code UNIQUE (Code);

CREATE UNIQUE NONCLUSTERED INDEX IX_UQ_Test_01_Code_Dup
    ON dbo.UQ_Test_01_ExactDupUC_and_Unique (Code);

INSERT INTO dbo.UQ_Test_01_ExactDupUC_and_Unique (Id, Code, Name)
VALUES (1, N'A', N'One'), (2, N'B', N'Two'), (3, N'C', N'Three');
GO

/*==============================================================================
  Table 02 — Two identical unique indexes (no constraint)
  Expected: EXACT_DUPLICATE
            Keep: higher-reads / lower-writes side; Drop: the other
==============================================================================*/
CREATE TABLE dbo.UQ_Test_02_ExactDupUniqueIndexes
(
    Id    INT           NOT NULL CONSTRAINT PK_UQ_Test_02 PRIMARY KEY,
    Email NVARCHAR(100) NOT NULL
);

CREATE UNIQUE NONCLUSTERED INDEX IX_UQ_Test_02_Email_A
    ON dbo.UQ_Test_02_ExactDupUniqueIndexes (Email);

CREATE UNIQUE NONCLUSTERED INDEX IX_UQ_Test_02_Email_B
    ON dbo.UQ_Test_02_ExactDupUniqueIndexes (Email);

INSERT INTO dbo.UQ_Test_02_ExactDupUniqueIndexes (Id, Email)
VALUES (1, N'a@test.local'), (2, N'b@test.local');
GO

/*==============================================================================
  Table 03 — UNIQUE constraint + unique index same keys, different INCLUDE
  Expected: DUPLICATE_KEY (same key, different includes)
==============================================================================*/
CREATE TABLE dbo.UQ_Test_03_UC_vs_UniqueIndex
(
    Id     INT           NOT NULL CONSTRAINT PK_UQ_Test_03 PRIMARY KEY,
    Sku    NVARCHAR(40)  NOT NULL,
    Color  NVARCHAR(20)  NULL,
    Weight DECIMAL(10,2) NULL
);

ALTER TABLE dbo.UQ_Test_03_UC_vs_UniqueIndex
    ADD CONSTRAINT UQ_Test_03_Sku UNIQUE (Sku);

CREATE UNIQUE NONCLUSTERED INDEX IX_UQ_Test_03_Sku_Inc
    ON dbo.UQ_Test_03_UC_vs_UniqueIndex (Sku)
    INCLUDE (Color, Weight);

INSERT INTO dbo.UQ_Test_03_UC_vs_UniqueIndex (Id, Sku, Color, Weight)
VALUES (1, N'SKU-1', N'Red', 1.1), (2, N'SKU-2', N'Blue', 2.2);
GO

/*==============================================================================
  Table 04 — Unique index duplicates PRIMARY KEY key columns
  Expected: DUPLICATE_KEY
            Keep: PK  Drop: IX_UQ_Test_04_Id_Unique
==============================================================================*/
CREATE TABLE dbo.UQ_Test_04_UniqueDuplicatesPK
(
    Id   INT          NOT NULL CONSTRAINT PK_UQ_Test_04 PRIMARY KEY,
    Note NVARCHAR(50) NULL
);

CREATE UNIQUE NONCLUSTERED INDEX IX_UQ_Test_04_Id_Unique
    ON dbo.UQ_Test_04_UniqueDuplicatesPK (Id);

INSERT INTO dbo.UQ_Test_04_UniqueDuplicatesPK (Id, Note)
VALUES (1, N'n1'), (2, N'n2');
GO

/*==============================================================================
  Table 05 — Unique index + non-unique index on the same key
  Expected: DUPLICATE_KEY
            Keep: unique side  Drop: non-unique IX
==============================================================================*/
CREATE TABLE dbo.UQ_Test_05_UniqueVsNonUniqueSameKey
(
    Id       INT          NOT NULL CONSTRAINT PK_UQ_Test_05 PRIMARY KEY,
    Username NVARCHAR(50) NOT NULL,
    Active   BIT          NOT NULL CONSTRAINT DF_UQ_Test_05_Active DEFAULT (1)
);

CREATE UNIQUE NONCLUSTERED INDEX IX_UQ_Test_05_Username_UQ
    ON dbo.UQ_Test_05_UniqueVsNonUniqueSameKey (Username);

CREATE NONCLUSTERED INDEX IX_UQ_Test_05_Username_NC
    ON dbo.UQ_Test_05_UniqueVsNonUniqueSameKey (Username);

INSERT INTO dbo.UQ_Test_05_UniqueVsNonUniqueSameKey (Id, Username)
VALUES (1, N'alice'), (2, N'bob');
GO

/*==============================================================================
  Table 06 — Same unique key columns, different ordinal order
  Expected: DUPLICATE_KEY (SORTED signature match)
==============================================================================*/
CREATE TABLE dbo.UQ_Test_06_UniqueKeyOrderDiffers
(
    Id   INT NOT NULL CONSTRAINT PK_UQ_Test_06 PRIMARY KEY,
    ColA INT NOT NULL,
    ColB INT NOT NULL
);

CREATE UNIQUE NONCLUSTERED INDEX IX_UQ_Test_06_A_B
    ON dbo.UQ_Test_06_UniqueKeyOrderDiffers (ColA, ColB);

CREATE UNIQUE NONCLUSTERED INDEX IX_UQ_Test_06_B_A
    ON dbo.UQ_Test_06_UniqueKeyOrderDiffers (ColB, ColA);

INSERT INTO dbo.UQ_Test_06_UniqueKeyOrderDiffers (Id, ColA, ColB)
VALUES (1, 10, 20), (2, 11, 21);
GO

/*==============================================================================
  Table 07 — Two unique indexes: (A) and (A,B) left-prefix overlap
  Expected: LEFT_PREFIX_UNIQUE_OVERLAP (BLOCKED — do not drop)
==============================================================================*/
CREATE TABLE dbo.UQ_Test_07_TwoUniqueLeftPrefix
(
    Id   INT NOT NULL CONSTRAINT PK_UQ_Test_07 PRIMARY KEY,
    ColA INT NOT NULL,
    ColB INT NOT NULL
);

CREATE UNIQUE NONCLUSTERED INDEX IX_UQ_Test_07_A
    ON dbo.UQ_Test_07_TwoUniqueLeftPrefix (ColA);

CREATE UNIQUE NONCLUSTERED INDEX IX_UQ_Test_07_A_B
    ON dbo.UQ_Test_07_TwoUniqueLeftPrefix (ColA, ColB);

INSERT INTO dbo.UQ_Test_07_TwoUniqueLeftPrefix (Id, ColA, ColB)
VALUES (1, 1, 10), (2, 2, 20);
GO

/*==============================================================================
  Table 08 — Unique (A,B) + non-unique left-prefix (A)
  Expected: REDUNDANT_LEFT_PREFIX
            Keep: unique wider  Drop candidate: non-unique narrower (REVIEW)
==============================================================================*/
CREATE TABLE dbo.UQ_Test_08_UniqueVsNonUniquePrefix
(
    Id      INT          NOT NULL CONSTRAINT PK_UQ_Test_08 PRIMARY KEY,
    ColA    INT          NOT NULL,
    ColB    INT          NOT NULL,
    Payload NVARCHAR(20) NULL
);

CREATE UNIQUE NONCLUSTERED INDEX IX_UQ_Test_08_A_B_UQ
    ON dbo.UQ_Test_08_UniqueVsNonUniquePrefix (ColA, ColB);

CREATE NONCLUSTERED INDEX IX_UQ_Test_08_A_NC
    ON dbo.UQ_Test_08_UniqueVsNonUniquePrefix (ColA);

INSERT INTO dbo.UQ_Test_08_UniqueVsNonUniquePrefix (Id, ColA, ColB, Payload)
VALUES (1, 1, 1, N'x'), (2, 1, 2, N'y'); -- same ColA allowed (unique is on A,B)
GO

/*==============================================================================
  Table 09 — Two unique indexes, same key, different INCLUDE lists
  Expected: DUPLICATE_KEY
==============================================================================*/
CREATE TABLE dbo.UQ_Test_09_IncludesDiffer
(
    Id      INT          NOT NULL CONSTRAINT PK_UQ_Test_09 PRIMARY KEY,
    AcctNo  NVARCHAR(30) NOT NULL,
    Region  NVARCHAR(10) NULL,
    Balance MONEY        NULL,
    Status  TINYINT      NULL
);

CREATE UNIQUE NONCLUSTERED INDEX IX_UQ_Test_09_Acct_IncRegion
    ON dbo.UQ_Test_09_IncludesDiffer (AcctNo)
    INCLUDE (Region);

CREATE UNIQUE NONCLUSTERED INDEX IX_UQ_Test_09_Acct_IncBalance
    ON dbo.UQ_Test_09_IncludesDiffer (AcctNo)
    INCLUDE (Balance, Status);

INSERT INTO dbo.UQ_Test_09_IncludesDiffer (Id, AcctNo, Region, Balance, Status)
VALUES (1, N'ACC-1', N'EAST', 100, 1), (2, N'ACC-2', N'WEST', 200, 2);
GO

/*==============================================================================
  Table 10 — Filtered unique indexes on same key, different filters
  Expected: DUPLICATE_KEY (same key; filters differ → REVIEW)
==============================================================================*/
CREATE TABLE dbo.UQ_Test_10_FilteredUnique
(
    Id         INT          NOT NULL CONSTRAINT PK_UQ_Test_10 PRIMARY KEY,
    ExternalId NVARCHAR(40) NULL,
    SourceSys  NVARCHAR(20) NULL
);

CREATE UNIQUE NONCLUSTERED INDEX IX_UQ_Test_10_ExtId_WhenNotNull
    ON dbo.UQ_Test_10_FilteredUnique (ExternalId)
    WHERE ExternalId IS NOT NULL;

CREATE UNIQUE NONCLUSTERED INDEX IX_UQ_Test_10_ExtId_WhenErp
    ON dbo.UQ_Test_10_FilteredUnique (ExternalId)
    WHERE SourceSys = N'ERP' AND ExternalId IS NOT NULL;

INSERT INTO dbo.UQ_Test_10_FilteredUnique (Id, ExternalId, SourceSys)
VALUES (1, N'E1', N'ERP'), (2, NULL, N'ERP'), (3, N'E2', N'CRM');
GO

/*------------------------------------------------------------------------------
  Sanity: list what was created
------------------------------------------------------------------------------*/
SELECT
    s.name AS schema_name,
    t.name AS table_name,
    i.name AS index_name,
    i.type_desc,
    i.is_primary_key,
    i.is_unique,
    i.is_unique_constraint,
    i.filter_definition
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON s.schema_id = t.schema_id
INNER JOIN sys.indexes AS i
    ON i.object_id = t.object_id
WHERE t.name LIKE N'UQ_Test_%'
  AND i.index_id > 0
ORDER BY t.name, i.index_id;

PRINT N'';
PRINT N'Test tables ready. Next:';
PRINT N'  SET @DatabaseList = N''<this_database>'' in duplicate_UQ_unique_index_details.sql and run it.';
PRINT N'Expected: findings on UQ_Test_01 through UQ_Test_10 (see comments above each table).';
GO

/*
------------------------------------------------------------------------------
Optional full cleanup (uncomment to remove all test objects)
------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.UQ_Test_10_FilteredUnique', N'U') IS NOT NULL DROP TABLE dbo.UQ_Test_10_FilteredUnique;
IF OBJECT_ID(N'dbo.UQ_Test_09_IncludesDiffer', N'U') IS NOT NULL DROP TABLE dbo.UQ_Test_09_IncludesDiffer;
IF OBJECT_ID(N'dbo.UQ_Test_08_UniqueVsNonUniquePrefix', N'U') IS NOT NULL DROP TABLE dbo.UQ_Test_08_UniqueVsNonUniquePrefix;
IF OBJECT_ID(N'dbo.UQ_Test_07_TwoUniqueLeftPrefix', N'U') IS NOT NULL DROP TABLE dbo.UQ_Test_07_TwoUniqueLeftPrefix;
IF OBJECT_ID(N'dbo.UQ_Test_06_UniqueKeyOrderDiffers', N'U') IS NOT NULL DROP TABLE dbo.UQ_Test_06_UniqueKeyOrderDiffers;
IF OBJECT_ID(N'dbo.UQ_Test_05_UniqueVsNonUniqueSameKey', N'U') IS NOT NULL DROP TABLE dbo.UQ_Test_05_UniqueVsNonUniqueSameKey;
IF OBJECT_ID(N'dbo.UQ_Test_04_UniqueDuplicatesPK', N'U') IS NOT NULL DROP TABLE dbo.UQ_Test_04_UniqueDuplicatesPK;
IF OBJECT_ID(N'dbo.UQ_Test_03_UC_vs_UniqueIndex', N'U') IS NOT NULL DROP TABLE dbo.UQ_Test_03_UC_vs_UniqueIndex;
IF OBJECT_ID(N'dbo.UQ_Test_02_ExactDupUniqueIndexes', N'U') IS NOT NULL DROP TABLE dbo.UQ_Test_02_ExactDupUniqueIndexes;
IF OBJECT_ID(N'dbo.UQ_Test_01_ExactDupUC_and_Unique', N'U') IS NOT NULL DROP TABLE dbo.UQ_Test_01_ExactDupUC_and_Unique;
*/
