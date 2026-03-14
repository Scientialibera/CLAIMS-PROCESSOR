param searchServiceName string
param location string
param sku string = 'basic'
param tags object = {}

resource search 'Microsoft.Search/searchServices@2023-11-01' = {
  name: searchServiceName
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    semanticSearch: 'free'
    hostingMode: 'default'
    publicNetworkAccess: 'enabled'
  }
}

output searchServiceName string = search.name
output searchServiceId string = search.id
output searchEndpoint string = 'https://${search.name}.search.windows.net'
