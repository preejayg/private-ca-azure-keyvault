@description('Name of the storage account')
param storageAccountName string

@description('Location for the storage account')
param location string = resourceGroup().location

@description('Storage account SKU')
param sku string = 'Standard_LRS'

@description('Tags to apply to the storage account')
param tags object = {}

@description('Public network access setting')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Disabled'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: sku
  }
  kind: 'StorageV2'
  tags: tags
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
    supportsHttpsTrafficOnly: true
  }
}

output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
output primaryEndpoints object = storageAccount.properties.primaryEndpoints
