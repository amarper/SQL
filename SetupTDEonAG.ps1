# Define parameters
$SqlServerPrimary = "PrimaryReplicaServer"
$SqlServerSecondary = "SecondaryReplicaServer"
$DatabaseName = "YourDatabaseName"
$CertBackupPath = "C:\Backup\TDECert"
$CertPassword = "StrongPassword123!"

# Load SQL Server PowerShell module
Import-Module SqlServer

# Function to create a master key
function Create-MasterKey {
    param ([string]$SqlServerInstance)

    $MasterKeyExists = Invoke-Sqlcmd -ServerInstance $SqlServerInstance -Query "
    SELECT COUNT(*) AS Count FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##';
    " | Select-Object -ExpandProperty Count

    if ($MasterKeyExists -eq 0) {
        Invoke-Sqlcmd -ServerInstance $SqlServerInstance -Query "
        USE master;
        CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$CertPassword';
        "
        Write-Output "Master key created on $SqlServerInstance."
    } else {
        Write-Output "Master key already exists on $SqlServerInstance."
    }
}

# Function to create and backup a certificate
function Create-Backup-Certificate {
    param ([string]$SqlServerInstance)

    $CertificateExists = Invoke-Sqlcmd -ServerInstance $SqlServerInstance -Query "
    SELECT COUNT(*) AS Count FROM sys.certificates WHERE name = 'TDECert';
    " | Select-Object -ExpandProperty Count

    if ($CertificateExists -eq 0) {
        Invoke-Sqlcmd -ServerInstance $SqlServerInstance -Query "
        CREATE CERTIFICATE TDECert
        WITH SUBJECT = 'TDE Certificate';
        "
        Invoke-Sqlcmd -ServerInstance $SqlServerInstance -Query "
        BACKUP CERTIFICATE TDECert TO FILE = '$CertBackupPath\TDECert.cer'
        WITH PRIVATE KEY (
            FILE = '$CertBackupPath\TDECert_PrivateKey.pvk',
            ENCRYPTION BY PASSWORD = '$CertPassword'
        );
        "
        Write-Output "Certificate created and backed up on $SqlServerInstance."
    } else {
        Write-Output "Certificate already exists on $SqlServerInstance."
    }
}

# Function to restore a certificate on secondary replica
function Restore-Certificate {
    param ([string]$SqlServerInstance)

    $CertificateExists = Invoke-Sqlcmd -ServerInstance $SqlServerInstance -Query "
    SELECT COUNT(*) AS Count FROM sys.certificates WHERE name = 'TDECert';
    " | Select-Object -ExpandProperty Count

    if ($CertificateExists -eq 0) {
        Invoke-Sqlcmd -ServerInstance $SqlServerInstance -Query "
        CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$CertPassword';
        CREATE CERTIFICATE TDECert
        FROM FILE = '$CertBackupPath\TDECert.cer'
        WITH PRIVATE KEY (
            FILE = '$CertBackupPath\TDECert_PrivateKey.pvk',
            DECRYPTION BY PASSWORD = '$CertPassword'
        );
        "
        Write-Output "Certificate restored on $SqlServerInstance."
    } else {
        Write-Output "Certificate already exists on $SqlServerInstance."
    }
}

# Function to enable TDE on the database
function Enable-TDE {
    param ([string]$SqlServerInstance, [string]$DatabaseName)

    $EncryptionEnabled = Invoke-Sqlcmd -ServerInstance $SqlServerInstance -Query "
    SELECT is_encrypted FROM sys.databases WHERE name = '$DatabaseName';
    " | Select-Object -ExpandProperty is_encrypted

    if ($EncryptionEnabled -eq 0) {
        Invoke-Sqlcmd -ServerInstance $SqlServerInstance -Query "
        USE $DatabaseName;
        CREATE DATABASE ENCRYPTION KEY
        WITH ALGORITHM = AES_256
        ENCRYPTION BY SERVER CERTIFICATE TDECert;
        ALTER DATABASE $DatabaseName
        SET ENCRYPTION ON;
        "
        Write-Output "TDE enabled on database $DatabaseName."
    } else {
        Write-Output "TDE is already enabled on database $DatabaseName."
    }
}

# Step 1: Create master key and certificate on primary replica
