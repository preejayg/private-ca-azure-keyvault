targetScope = 'resourceGroup'

// ============================================
// NETWORKING REQUIREMENTS & CONSTRAINTS
// ============================================
//
// This deployment creates a Function App with private networking:
//
// 1. PRIVATE DNS ZONES (REQUIRED):
//    The following private DNS zones must be created and linked to the VNet
//    by your platform team (organizational policy blocks Bicep creation):
//    - privatelink.vaultcore.azure.net
//    - privatelink.blob.core.windows.net
//    - privatelink.file.core.windows.net
//    - privatelink.azurewebsites.net
//
// 2. SERVICE ENDPOINTS (REQUIRED):
//    The function app subnet (snet-functionapp-integration) must have
//    Microsoft.Storage service endpoint enabled. Contact your network team
//    if this is managed by account vending.
//
// 3. STORAGE FIREWALL:
//    After service endpoint is added, run:
//    ./scripts/configure-storage-network.sh
//
// 4. VNET INTEGRATION:
//    Function app is configured with:
//    - VNet integration to snet-functionapp-integration
//    - WEBSITE_VNET_ROUTE_ALL=1 (routes all traffic through VNet)
//    - WEBSITE_DNS_SERVER=168.63.129.16 (Azure DNS for private endpoint resolution)
//
// 5. MANAGED IDENTITY:
//    Function app uses system-assigned managed identity with:
//    - Storage Blob Data Owner role on storage account
//    - Key Vault access policy for certificates, keys, secrets
//
// ============================================

@description('Environment name')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string

@description('Location for all resources')
param location string = resourceGroup().location

@description('Object ID for Key Vault access')
param objectId string

@description('Application tag value')
param applicationTag string = 'DeviceCertificateManagement-POC'

@description('Cost Centre tag value')
param costCentreTag string = 'ce'

@description('Managed By tag value')
param managedByTag string = 'infrastructure-team'

@description('Existing VNet name for private endpoint')
param existingVNetName string

@description('Existing VNet resource group')
param existingVNetResourceGroup string

@description('Existing subnet name for private endpoint')
param existingSubnetName string

@description('Existing subnet name for Function App VNet integration')
param functionAppSubnetName string

@description('Enable private endpoint for Key Vault')
param enablePrivateEndpoint bool = true

@description('Deploy Function App for certificate management')
param deployFunctionApp bool = false

// Common tags for all resources
var commonTags = {
  Application: applicationTag
  CostCentre: costCentreTag
  Environment: environment
  ManagedBy: managedByTag
}

// Naming convention: resource-env-location-project-sequence
var locationCode = 'aue' // australiaeast
var naming = {
  keyVault: 'kv-${environment}-${locationCode}-dcert-poc-001'
  privateEndpoint: 'pe-${environment}-${locationCode}-kv-dcert-poc'
  storageAccount: 'stfunc${environment}devicepki001'
  appServicePlan: 'asp-devicepki-${environment}-001'
  functionApp: 'func-devicepki-${environment}-001'
  storagePEBlob: 'pe-${environment}-${locationCode}-storage-blob-dcert-poc'
  storagePEFile: 'pe-${environment}-${locationCode}-storage-file-dcert-poc'
  functionAppPE: 'pe-${environment}-${locationCode}-functionapp-dcert-poc'
}

// Get existing VNet subnet for private endpoint
resource existingVNet 'Microsoft.Network/virtualNetworks@2023-05-01' existing = {
  name: existingVNetName
  scope: resourceGroup(existingVNetResourceGroup)
}

resource existingSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' existing = {
  name: existingSubnetName
  parent: existingVNet
}

resource functionAppSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' existing = if (deployFunctionApp) {
  name: functionAppSubnetName
  parent: existingVNet
}

// ============================================
// Private DNS Zones
// ============================================
// NOTE: Private DNS Zone creation is blocked by organizational policy.
// DNS zones must be managed centrally by the platform team.
// Private endpoints will be created without automatic DNS registration.
// You will need to manually add DNS records or request the platform team
// to create and link private DNS zones:
//   - privatelink.vaultcore.azure.net
//   - privatelink.blob.core.windows.net
//   - privatelink.file.core.windows.net
//   - privatelink.azurewebsites.net

// Phase 1: Deploy Key Vault
module keyVault 'modules/keyvault/keyvault.bicep' = {
  name: 'keyVaultDeployment'
  params: {
    keyVaultName: take(naming.keyVault, 24) // Key Vault names max 24 chars
    location: location
    objectId: objectId
    environment: environment
    tags: commonTags
    publicNetworkAccess: enablePrivateEndpoint ? 'Disabled' : 'Enabled'
  }
}

// Reference to deployed Key Vault for RBAC role assignments
resource keyVaultResource 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: take(naming.keyVault, 24)
  dependsOn: [
    keyVault
  ]
}

// Phase 2: Deploy Private Endpoint
module privateEndpoint 'modules/privateendpoint/privateendpoint.bicep' = if (enablePrivateEndpoint) {
  name: 'privateEndpointDeployment'
  params: {
    privateEndpointName: naming.privateEndpoint
    location: location
    subnetId: existingSubnet.id
    privateLinkServiceId: keyVault.outputs.keyVaultId
    groupIds: ['vault']
    tags: commonTags
    privateDnsZoneIds: [] // DNS zone groups added post-deployment via CLI (permissions issue)
  }
}

// Phase 3: Deploy Storage Account for Function App
module storageAccount 'modules/storage/storage.bicep' = if (deployFunctionApp) {
  name: 'storageAccountDeployment'
  params: {
    storageAccountName: naming.storageAccount
    location: location
    tags: commonTags
    publicNetworkAccess: 'Disabled'
  }
}

// Phase 4: Deploy Storage Private Endpoints (Blob)
module storagePEBlob 'modules/privateendpoint/privateendpoint.bicep' = if (deployFunctionApp) {
  name: 'storagePEBlobDeployment'
  params: {
    privateEndpointName: naming.storagePEBlob
    location: location
    subnetId: existingSubnet.id
    privateLinkServiceId: storageAccount!.outputs.storageAccountId
    groupIds: ['blob']
    tags: commonTags
    privateDnsZoneIds: [] // DNS zone groups added post-deployment via CLI (permissions issue)
  }
}

// Phase 5: Deploy Storage Private Endpoints (File)
module storagePEFile 'modules/privateendpoint/privateendpoint.bicep' = if (deployFunctionApp) {
  name: 'storagePEFileDeployment'
  params: {
    privateEndpointName: naming.storagePEFile
    location: location
    subnetId: existingSubnet.id
    privateLinkServiceId: storageAccount!.outputs.storageAccountId
    groupIds: ['file']
    tags: commonTags
    privateDnsZoneIds: [] // DNS zone groups added post-deployment via CLI (permissions issue)
  }
}

// Phase 6: Deploy Function App
module functionApp 'modules/functionapp/functionapp.bicep' = if (deployFunctionApp) {
  name: 'functionAppDeployment'
  params: {
    functionAppName: naming.functionApp
    appServicePlanName: naming.appServicePlan
    location: location
    storageAccountName: storageAccount!.outputs.storageAccountName
    subnetId: functionAppSubnet!.id
    keyVaultName: keyVault.outputs.keyVaultName
    tags: commonTags
  }
  dependsOn: [
    storagePEBlob
    storagePEFile
  ]
}

// Phase 6.5: Deploy Function App Private Endpoint
module functionAppPE 'modules/privateendpoint/privateendpoint.bicep' = if (deployFunctionApp) {
  name: 'functionAppPEDeployment'
  params: {
    privateEndpointName: naming.functionAppPE
    location: location
    subnetId: existingSubnet.id
    privateLinkServiceId: functionApp!.outputs.functionAppId
    groupIds: ['sites']
    tags: commonTags
    // privateDnsZoneIds: [] // DNS zones blocked by policy - manual DNS required
  }
}

// Phase 7: Grant Storage RBAC roles to Function App
resource storageBlobDataOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployFunctionApp) {
  name: guid(subscription().id, resourceGroup().id, naming.storageAccount, naming.functionApp, 'BlobOwner')
  scope: storageAccount!
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
    ) // Storage Blob Data Owner
    principalId: functionApp!.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageBlobDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployFunctionApp) {
  name: guid(subscription().id, resourceGroup().id, naming.storageAccount, naming.functionApp, 'BlobContrib')
  scope: storageAccount!
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    ) // Storage Blob Data Contributor
    principalId: functionApp!.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageFileDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployFunctionApp) {
  name: guid(subscription().id, resourceGroup().id, naming.storageAccount, naming.functionApp, 'FileContrib')
  scope: storageAccount!
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '0c867c2a-1d8c-454a-a3db-ab2ea1bdc8bb'
    ) // Storage File Data Privileged Contributor
    principalId: functionApp!.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageQueueDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployFunctionApp) {
  name: guid(subscription().id, resourceGroup().id, naming.storageAccount, naming.functionApp, 'QueueContrib')
  scope: storageAccount!
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
    ) // Storage Queue Data Contributor
    principalId: functionApp!.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

// Phase 8: Grant Key Vault RBAC roles to Function App
// Using RBAC instead of access policies for better security and audit trail
resource keyVaultCertificatesOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployFunctionApp) {
  name: guid(subscription().id, resourceGroup().id, naming.keyVault, naming.functionApp, 'CertOfficer')
  scope: keyVaultResource
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'a4417e6f-fecd-4de8-b567-7b0420556985'
    ) // Key Vault Certificates Officer
    principalId: functionApp!.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

resource keyVaultCryptoOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployFunctionApp) {
  name: guid(subscription().id, resourceGroup().id, naming.keyVault, naming.functionApp, 'CryptoOfficer')
  scope: keyVaultResource
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '14b46e9e-c2b7-41b4-b07b-48a6ebf60603'
    ) // Key Vault Crypto Officer  
    principalId: functionApp!.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

resource keyVaultSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployFunctionApp) {
  name: guid(subscription().id, resourceGroup().id, naming.keyVault, naming.functionApp, 'SecretsUser')
  scope: keyVaultResource
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '4633458b-17de-408a-b874-0445c86b69e6'
    ) // Key Vault Secrets User
    principalId: functionApp!.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

resource keyVaultSecretsOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployFunctionApp) {
  name: guid(subscription().id, resourceGroup().id, naming.keyVault, naming.functionApp, 'SecretsOfficer')
  scope: keyVaultResource
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
    ) // Key Vault Secrets Officer
    principalId: functionApp!.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

// Phase 2: IoT Hub (commented out for now)
// module iotHub 'modules/iot-hub/iothub.bicep' = {
//   name: 'iotHubDeployment'
//   params: {
//     iotHubName: naming.iotHub
//     location: location
//     environment: environment
//     tags: commonTags
//     keyVaultName: keyVault.outputs.keyVaultName
//   }
// }

// Outputs
output keyVaultName string = keyVault.outputs.keyVaultName
output keyVaultUri string = keyVault.outputs.keyVaultUri
output keyVaultId string = keyVault.outputs.keyVaultId
output privateEndpointName string = enablePrivateEndpoint
  ? privateEndpoint!.outputs.privateEndpointName
  : 'Not deployed'
output privateEndpointId string = enablePrivateEndpoint ? privateEndpoint!.outputs.privateEndpointId : 'Not deployed'
output privateIP string = enablePrivateEndpoint ? privateEndpoint!.outputs.privateIPAddress : 'Not deployed'
output functionAppName string = deployFunctionApp ? functionApp!.outputs.functionAppName : 'Not deployed'
output functionAppId string = deployFunctionApp ? functionApp!.outputs.functionAppId : 'Not deployed'
output functionAppPrincipalId string = deployFunctionApp ? functionApp!.outputs.principalId : 'Not deployed'
output functionAppPrivateEndpointName string = deployFunctionApp
  ? functionAppPE!.outputs.privateEndpointName
  : 'Not deployed'
output functionAppPrivateIP string = deployFunctionApp ? functionAppPE!.outputs.privateIPAddress : 'Not deployed'
output storageAccountName string = deployFunctionApp ? storageAccount!.outputs.storageAccountName : 'Not deployed'
output resourceGroupName string = resourceGroup().name
output environment string = environment
output kvPrivateIP string = enablePrivateEndpoint ? privateEndpoint!.outputs.privateIPAddress : 'Not deployed'
output storageBlobPrivateIP string = deployFunctionApp ? storagePEBlob!.outputs.privateIPAddress : 'Not deployed'
output storageFilePrivateIP string = deployFunctionApp ? storagePEFile!.outputs.privateIPAddress : 'Not deployed'
