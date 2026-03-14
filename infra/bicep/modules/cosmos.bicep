param accountName string
param location string
param databaseName string
param ledgerContainerName string
param recordsContainerName string
param tags object = {}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2023-11-15' = {
  name: accountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    publicNetworkAccess: 'Enabled'
    enableFreeTier: false
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    capabilities: []
  }
}

resource sqlDb 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-11-15' = {
  name: '${cosmos.name}/${databaseName}'
  properties: {
    resource: {
      id: databaseName
    }
  }
}

resource ledgerContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-11-15' = {
  name: '${cosmos.name}/${databaseName}/${ledgerContainerName}'
  properties: {
    resource: {
      id: ledgerContainerName
      partitionKey: {
        paths: ['/claim_id']
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
      }
    }
    options: {
      throughput: 400
    }
  }
}

resource recordsContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-11-15' = {
  name: '${cosmos.name}/${databaseName}/${recordsContainerName}'
  properties: {
    resource: {
      id: recordsContainerName
      partitionKey: {
        paths: ['/claim_id']
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
      }
    }
    options: {
      throughput: 400
    }
  }
}

output accountName string = cosmos.name
output accountId string = cosmos.id
output endpoint string = cosmos.properties.documentEndpoint
output databaseName string = sqlDb.name
output ledgerContainerName string = ledgerContainerName
output recordsContainerName string = recordsContainerName
