using '../bicep/main.bicep'

param environment = 'dev'
param location = 'australiaeast'
param objectId = '3bb39574-e7e8-46c3-a2d1-05e4777a8978' // TODO: Add your Object ID here - run: az ad signed-in-user show --query id -o tsv

// Tags from setup-keyvault.sh script
param applicationTag = 'DeviceCertificateManagement-POC'
param costCentreTag = 'ce'
param managedByTag = 'infrastructure-team'

// Private Endpoint VNet Configuration
param existingPrivateEndpointVNetName = 'vnet-network-dev-aue-001'
param existingPrivateEndpointVNetResourceGroup = 'rg-network-dev-aue-001'
param existingPrivateEndpointSubnetName = 'snet-privateendpoint'
param enablePrivateEndpoint = true

// Function App Configuration
param deployFunctionApp = true // Function App deployment enabled
param functionAppSubnetName = 'snet-functionapp-integration'
