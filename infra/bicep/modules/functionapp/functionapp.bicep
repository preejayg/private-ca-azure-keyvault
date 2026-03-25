@description('Name of the Function App')
param functionAppName string

@description('Name of the App Service Plan')
param appServicePlanName string

@description('Location for resources')
param location string = resourceGroup().location

@description('Storage account name for Function App')
param storageAccountName string

@description('Subnet resource ID for VNet integration')
param subnetId string

@description('Key Vault name for app settings')
param keyVaultName string

@description('Runtime stack')
@allowed([
  'python'
  'node'
  'dotnet'
  'java'
])
param runtime string = 'python'

@description('Runtime version')
param runtimeVersion string = '3.11'

@description('Tags to apply to resources')
param tags object = {}

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: 'B1'
    tier: 'Basic'
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    publicNetworkAccess: 'Disabled'
    virtualNetworkSubnetId: subnetId
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: '${runtime}|${runtimeVersion}'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      appSettings: [
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storageAccountName
        }
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
        {
          name: 'WEBSITE_CONTENTOVERVNET'
          value: '1'
        }
        {
          name: 'WEBSITE_VNET_ROUTE_ALL'
          value: '1'
        }
        {
          name: 'WEBSITE_DNS_SERVER'
          value: '168.63.129.16'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: runtime
        }
        {
          name: 'KEY_VAULT_NAME'
          value: keyVaultName
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
        {
          name: 'ENABLE_ORYX_BUILD'
          value: 'true'
        }
      ]
    }
  }
}

// VNet integration (already configured via virtualNetworkSubnetId above, but ensuring it's established)
resource networkConfig 'Microsoft.Web/sites/networkConfig@2023-01-01' = {
  parent: functionApp
  name: 'virtualNetwork'
  properties: {
    subnetResourceId: subnetId
    swiftSupported: true
  }
}

output functionAppId string = functionApp.id
output functionAppName string = functionApp.name
output principalId string = functionApp.identity.principalId
output appServicePlanId string = appServicePlan.id
