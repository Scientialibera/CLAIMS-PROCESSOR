param storageAccountName string
param location string
param blobContainerName string = 'claims'
param tags object = {}

resource stg 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

resource blobSvc 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  name: '${stg.name}/default'
}

resource claimsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: '${stg.name}/default/${blobContainerName}'
  properties: {
    publicAccess: 'None'
  }
}

output storageAccountName string = stg.name
output storageAccountId string = stg.id
output blobContainerName string = claimsContainer.name
output blobAccountUrl string = stg.properties.primaryEndpoints.blob
