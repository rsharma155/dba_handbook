/*
================================================================================
Renamed / superseded
================================================================================
This script was renamed to:

  sql_server/03_Storage_Engine/object_dependencies.sql

That version supports:
  - Tables, views, TVFs, functions, and procedures as targets
  - Single or comma-separated @ObjectList
  - Optional @ColumnName and @DatabaseName guard

Open object_dependencies.sql and run it in your USER database
(not master), after setting @ObjectList to real object names.
================================================================================
*/
RAISERROR(
    N'table_dependencies.sql was renamed to object_dependencies.sql. Open that script, USE your user database, set @ObjectList, then run.',
    16, 1);
