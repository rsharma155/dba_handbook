# DBA Repository — PostgreSQL

Creates the `dba_repository` database and `dba` schema for framework objects, baselines, and governance.

```bash
psql -h HOST -U postgres -f 00_create_repository.sql
```

Then deploy framework: `../00_Framework/00_Deploy_Framework.sql`
