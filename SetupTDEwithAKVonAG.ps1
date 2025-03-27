# Define parameters
$SqlServerPrimary = "PrimaryReplicaServer"
$SqlServerSecondary = "SecondaryReplicaServer"
$DatabaseName = "YourDatabaseName"
$KeyVaultName = "YourKeyVaultName"
$SecretName = "YourSecretName"

# Load the required modules
Import-Module Az -ErrorAction Stop
Import-Module SqlServer -ErrorAction Stop

# Step 1: Authenticate with Azure
# Authenticate automatically using a service principal or managed identity
Connect-AzAccount -Identity

# Step 2: Retrieve the secret from Azure Key Vault
$Secret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName
$CertPassword = $Secret.SecretValueText # Encryption key from Azure Key Vault

# Step 3: Function to create a master key
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

# Step 4: Function to create and backup a certificate
function Create-Backup-Certificate {
    param ([string]$SqlServerInstance, [string]$CertBackupPath)

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

# Step 5: Function to restore a certificate on secondary replicas
function Restore-Certificate {
    param ([string]$SqlServerInstance, [string]$CertBackupPath)

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

# Step 6: Function to enable TDE on the database
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

# Step 7: Execute the steps
$CertBackupPath = "C:\Backup\TDECert"
New-Item -ItemType Directory -Force -Path $CertBackupPath | Out-Null

# Create master key and certificate on the primary replica
Create-MasterKey -SqlServerInstance $SqlServerPrimary
Create-Backup-Certificate -SqlServerInstance $SqlServerPrimary -CertBackupPath $CertBackupPath

# Restore the certificate on the secondary replica
Restore-Certificate -SqlServerInstance $SqlServerSecondary -CertBackupPath $CertBackupPath

# Enable TDE on the primary replica
Enable-TDE -SqlServerInstance $SqlServerPrimary -DatabaseName $DatabaseName
