# SQL Server Connectivity Libraries

## Recommended: JDBC (cross-platform)

Place the Microsoft JDBC driver JAR here:

```
mssql-jdbc-12.8.1.jre11.jar
```

Works on Windows, macOS, and Linux without a system ODBC install.

## Optional: ODBC Driver 18

For environments that mandate ODBC, extract the Microsoft ODBC Driver 18 redistributable under:

```
odbc/
```

The Java connector can use ODBC on Windows via JNI in a future release. Today the portable bundle uses the JDBC driver in this folder.

Connection properties supported in the UI:

| Property | Example |
|----------|---------|
| Server | `prod-sql01` or `prod-sql01,1433` |
| Database | `DBARepository` |
| Auth | Windows integrated (Windows only) or SQL login |
| Encrypt / trust cert | Azure SQL, self-signed certs |
