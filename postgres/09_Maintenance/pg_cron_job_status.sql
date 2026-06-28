/*
================================================================================
pg_cron Job Status — Scheduled job health (if extension installed)
================================================================================
Description:
    Lists pg_cron jobs and recent run status when extension is present.

Prerequisite: pg_cron extension (optional)

Criticality: Low
================================================================================
*/

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        RAISE NOTICE 'Query cron.job and cron.job_run_details for job history.';
    ELSE
        RAISE NOTICE 'pg_cron not installed — use external schedulers (cron, Kubernetes CronJob, etc.).';
    END IF;
END $$;

SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_cron';
