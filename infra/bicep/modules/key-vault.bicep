param keyVaultName string
param location string
param tags object = {}

resource kv 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    publicNetworkAccess: 'Enabled'
  }
}

output keyVaultName string = kv.name
output keyVaultId string = kv.id
output keyVaultUri string = kv.properties.vaultUri
