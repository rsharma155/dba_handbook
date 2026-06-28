# Preventive Measures — PostgreSQL

Optional governance layer for production PostgreSQL:

1. `01_create_governance_schema.sql` — tables and default policies
2. `02_capture_long_queries.sql` — scheduled via pg_cron or external scheduler
3. `03_blocking_detection.sql` — capture blocking incidents
4. `04_statement_timeout_policy.sql` — timeout configuration review
5. `05_alert_views.sql` — monitoring views

Schedule `02` and `03` every 1–5 minutes during business hours using pg_cron, Patroni hooks, or your monitoring agent.
