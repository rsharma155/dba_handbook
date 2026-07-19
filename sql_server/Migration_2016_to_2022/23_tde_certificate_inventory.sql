/*
    Migration 2016 -> 2022 | TDE certificate inventory
    BACK UP certificates and service master key before migration/cutover.
    Risk: Read-only
*/
SET NOCOUNT ON;

SELECT
    d.name AS [DatabaseName],
    d.is_encrypted,
    dek.encryption_state_desc,
    dek.key_algorithm,
    dek.key_length,
    c.name AS [CertificateName],
    c.pvt_key_encryption_type_desc,
    c.expiry_date,
    c.pvt_key_last_backup_date
FROM sys.databases AS d
LEFT JOIN sys.dm_database_encryption_keys AS dek ON d.database_id = dek.database_id
LEFT JOIN sys.certificates AS c ON dek.encryptor_thumbprint = c.thumbprint
WHERE d.database_id > 4
ORDER BY d.name;

SELECT name, pvt_key_last_backup_date, expiry_date, subject
FROM sys.certificates
WHERE pvt_key_last_backup_date IS NULL OR pvt_key_last_backup_date < DATEADD(YEAR, -1, GETDATE())
ORDER BY name;

-- Backup templates (run from secure admin session; store offline):
-- BACKUP SERVICE MASTER KEY TO FILE = 'D:\Backup\SKM.key' ENCRYPTION BY PASSWORD = 'StrongPassword!';
-- BACKUP CERTIFICATE [TDE_Cert_Name] TO FILE = 'D:\Backup\TDE_Cert.cer'
--   WITH PRIVATE KEY (FILE = 'D:\Backup\TDE_Cert.pvk', ENCRYPTION BY PASSWORD = 'StrongPassword!');
