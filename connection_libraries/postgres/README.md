# PostgreSQL JDBC Driver

Place the official PostgreSQL JDBC JAR here:

```
postgresql-42.7.4.jar
```

The unified connector loads it via `java -cp` from `connection_libraries/postgres/`.

Connection properties supported in the UI:

| Property | Example |
|----------|---------|
| Host | `pg-prod.corp.local` |
| Port | `5432` |
| Database | `dba_repository` |
| User / password | `dba_readonly` |
| SSL mode | `prefer`, `require`, `verify-full` |
