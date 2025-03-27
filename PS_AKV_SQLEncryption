# Step 1: Install Azure PowerShell module
Install-Module -Name Az -AllowClobber -Scope CurrentUser

# Step 2: Connect to Azure
Connect-AzAccount

# Step 3: Set variables
$ResourceGroupName = "YourResourceGroupName"
$KeyVaultName = "YourKeyVaultName"
$KeyName = "YourKeyName"
$SqlServerInstance = "YourSqlServerInstance"
$DatabaseName = "YourDatabaseName"

------ ALREADY COMPLETD ------
# Step 4: Create a key in Azure Key Vault
New-AzKeyVaultKey -VaultName $KeyVaultName -Name $KeyName -KeyType RSA -KeySize 2048

# Step 5: Grant SQL Server access to the Key Vault
$SqlServerServicePrincipal = "YourSQLServerServicePrincipal"
Set-AzKeyVaultAccessPolicy -VaultName $KeyVaultName -ServicePrincipalName $SqlServerServicePrincipal -PermissionsToKeys get,wrapKey,unwrapKey
------ ALREADY COMPLETD ------

# Step 4: Retrieve the secret (encryption key) from Azure Key Vault
$Secret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $KeyName

# Step 6: Configure SQL Server for TDE
# Load the SQL Server PowerShell module
Import-Module SqlServer

# Create a credential for Azure Key Vault secret
Invoke-Sqlcmd -ServerInstance $SqlServerInstance -Query "
CREATE CREDENTIAL [AzureKeyVaultCredential]
WITH IDENTITY = 'YourAzureKeyVaultIdentity',
SECRET = '$($Secret.SecretValueText)';
"

# Create a database encryption key using the Azure Key Vault key
Invoke-Sqlcmd -ServerInstance $SqlServerInstance -Query "
USE $DatabaseName;
CREATE DATABASE ENCRYPTION KEY
WITH ALGORITHM = AES_256
ENCRYPTION BY SERVER CERTIFICATE [AzureKeyVaultCredential];
"

# Enable TDE on the database
Invoke-Sqlcmd -ServerInstance $SqlServerInstance -Query "
ALTER DATABASE $DatabaseName
SET ENCRYPTION ON;
"
