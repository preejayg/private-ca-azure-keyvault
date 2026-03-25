@description('Name of the private endpoint')
param privateEndpointName string

@description('Location for the private endpoint')
param location string

@description('Subnet ID where the private endpoint will be created')
param subnetId string

@description('Resource ID of the private link service')
param privateLinkServiceId string

@description('Group IDs for the private endpoint')
param groupIds array

@description('Resource tags')
param tags object

@description('Private DNS Zone IDs for automatic DNS registration (optional)')
param privateDnsZoneIds array = []

// Private Endpoint Resource
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: privateEndpointName
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${privateEndpointName}-connection'
        properties: {
          privateLinkServiceId: privateLinkServiceId
          groupIds: groupIds
        }
      }
    ]
  }
}

// Private DNS Zone Group (if DNS Zone IDs are provided)
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = if (!empty(privateDnsZoneIds)) {
  name: 'default'
  parent: privateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      for (zoneId, i) in privateDnsZoneIds: {
        name: 'config${i}'
        properties: {
          privateDnsZoneId: zoneId
        }
      }
    ]
  }
}

// Outputs
output privateEndpointId string = privateEndpoint.id
output privateEndpointName string = privateEndpoint.name
output privateIPAddress string = privateEndpoint.properties.customDnsConfigs[0].ipAddresses[0]
output connectionStatus string = privateEndpoint.properties.privateLinkServiceConnections[0].properties.privateLinkServiceConnectionState.status
