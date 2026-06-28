# Connection Libraries (deprecated for runtime)

JDBC JAR files were used by the **legacy Java connector**. The native **Go** binary (`cmd/dba-console`) embeds SQL drivers at compile time — **no JARs are needed at runtime**.

This folder is kept only for reference or if you maintain the deprecated Java build in `connector/`.

## Layout

```
connection_libraries/
├── postgres/
│   └── postgresql-*.jar          # PostgreSQL JDBC driver
└── sqlserver/
    ├── mssql-jdbc-*.jar          # Microsoft JDBC driver (cross-platform, recommended)
    └── odbc/                     # Optional: Microsoft ODBC Driver 18 redistributable (Windows/Linux)
        └── README.md
```

## Download (maintainers)

Run from repo root after cloning:

```bash
./unified_console/scripts/fetch-drivers.sh
```

Or download manually:

| Engine | Library | URL |
|--------|---------|-----|
| PostgreSQL | `postgresql-42.7.4.jar` | https://jdbc.postgresql.org/download/ |
| SQL Server | `mssql-jdbc-12.8.1.jre11.jar` | https://learn.microsoft.com/en-us/sql/connect/jdbc/download-microsoft-jdbc-driver-for-sql-server |
| SQL Server ODBC (optional) | ODBC Driver 18 | https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server |

## Licensing

- PostgreSQL JDBC: BSD-2-Clause
- Microsoft JDBC / ODBC: Microsoft license terms — redistribute only per their EULA

## Git policy

JARs and ODBC binaries are **not** committed (`.gitignore`). CI and release packaging runs `fetch-drivers.sh` before building the portable bundle.
