using '../bicep/main.bicep'

param environment =
//TODO: Add your environment here (e.g., 'dev', 'test', 'prod')
param location =
//TODO: Add your location here (e.g., 'australiaeast', 'uksouth', 'eastus2')
param objectId =
// TODO: Add your Object ID here - run: az ad signed-in-user show --query id -o tsv

// Tags from setup-keyvault.sh script
param applicationTag =
//TODO: Add your application tag here (e.g., 'DeviceCertificateManagement')
param costCentreTag =
//TODO: Add your cost centre tag here 
param managedByTag =
//TODO: Add your managed by tag here (e.g., 'infrastructure-team')

// Private Endpoint VNet Configuration
param existingPrivateEndpointVNetName =
//TODO: Add your private endpoint VNet name here (e.g., 'vnet-network-dev-aue-001')
param existingPrivateEndpointVNetResourceGroup =
//TODO: Add your private endpoint VNet resource group here (e.g., 'rg-network-dev-aue-001')
param existingPrivateEndpointSubnetName =
//TODO: Add your private endpoint subnet name here (e.g., 'snet-privateendpoint')
param enablePrivateEndpoint =
//TODO: Enable or disable private endpoint (true/false)

// Function App Configuration
param deployFunctionApp = true // Function App deployment enabled
param functionAppSubnetName =
//tODO: Add your Function App subnet name here (e.g., 'snet-functionapp')
