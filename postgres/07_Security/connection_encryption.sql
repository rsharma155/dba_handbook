/*
================================================================================
Connection Encryption — SSL/TLS configuration review
================================================================================
Description:
    Server SSL settings and current connection SSL usage.

Action:  Enable ssl=on; use hostssl in pg_hba.conf; require TLS 1.2+ in production.

Criticality: High
================================================================================
*/

SELECT name, setting, short_desc
FROM pg_settings
WHERE name IN ('ssl', 'ssl_cert_file', 'ssl_key_file', 'ssl_ca_file', 'ssl_min_protocol_version');

SELECT pid, usename, datname, client_addr, ssl, version, cipher
FROM pg_stat_ssl s
JOIN pg_stat_activity a ON a.pid = s.pid
WHERE a.backend_type = 'client backend';

SELECT count(*) FILTER (WHERE ssl) AS ssl_connections,
       count(*) FILTER (WHERE NOT ssl) AS non_ssl_connections
FROM pg_stat_ssl s
JOIN pg_stat_activity a ON a.pid = s.pid
WHERE a.backend_type = 'client backend';
