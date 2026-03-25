@description('The name of the Key Vault')
param keyVaultName string

@description('Location for all resources')
param location string

@description('Environment name')
param environment string

@description('Object ID of the user or service principal to grant access')
param objectId string

@description('Resource tags')
param tags object

@description('Tenant ID for the Azure Active Directory')
param tenantId string = subscription().tenantId

@description('Enable public network access (set to Disabled when using Private Endpoints)')
param publicNetworkAccess string = 'Disabled'

// Environment-specific configurations for Device Identity project
var environmentConfig = {
  dev: {
    sku: 'standard'
    enablePurgeProtection: false
    networkAclsDefaultAction: 'Deny'
    softDeleteRetentionInDays: 7
  }
  test: {
    sku: 'standard'
    enablePurgeProtection: false
    networkAclsDefaultAction: 'Deny'
    softDeleteRetentionInDays: 30
  }
  prod: {
    sku: 'premium'
    enablePurgeProtection: true
    networkAclsDefaultAction: 'Deny' // Restrict in production
    softDeleteRetentionInDays: 90
  }
}

var config = environmentConfig[environment]

// Key Vault Resource
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: config.sku
    }
    tenantId: tenantId
    enabledForDeployment: true
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true // Allow ARM/Bicep deployments
    enableSoftDelete: true
    softDeleteRetentionInDays: config.softDeleteRetentionInDays
    enablePurgeProtection: config.enablePurgeProtection ? true : null
    enableRbacAuthorization: true // Use RBAC instead of access policies for better security
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      defaultAction: config.networkAclsDefaultAction
      bypass: 'AzureServices'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

// Diagnostic Settings for audit logging (optional but recommended)
// Uncomment when Log Analytics workspace is available
// resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
//   name: '${keyVaultName}-diagnostics'
//   scope: keyVault
//   properties: {
//     workspaceId: logAnalyticsWorkspaceId
//     logs: [
//       {
//         category: 'AuditEvent'
//         enabled: true
//       }
//     ]
//     metrics: [
//       {
//         category: 'AllMetrics'
//         enabled: true
//       }
//     ]
//   }
// }

// Grant administrator RBAC roles for Key Vault management
// Key Vault Administrator role for the deployer/admin user
resource keyVaultAdministrator 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, objectId, 'KeyVaultAdministrator')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '00482a5a-887f-4fb3-b363-3b7fe8e74483'
    ) // Key Vault Administrator
    principalId: objectId
    principalType: 'User'
  }
}

// Outputs
output keyVaultId string = keyVault.id
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
