param location string
param secondaryLocation string
param deployOpenAI bool = true
param deployDocIntel bool = true
param openAiName string
param docIntelName string
param openAiSku string = 'S0'
param docIntelSku string = 'S0'
param tags object = {}

resource openAi 'Microsoft.CognitiveServices/accounts@2023-05-01' = if (deployOpenAI) {
  name: openAiName
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: openAiSku
  }
  properties: {
    customSubDomainName: openAiName
    publicNetworkAccess: 'Enabled'
  }
}

resource docIntel 'Microsoft.CognitiveServices/accounts@2023-05-01' = if (deployDocIntel) {
  name: docIntelName
  location: secondaryLocation
  tags: tags
  kind: 'FormRecognizer'
  sku: {
    name: docIntelSku
  }
  properties: {
    customSubDomainName: docIntelName
    publicNetworkAccess: 'Enabled'
  }
}

output openAiName string = deployOpenAI ? openAi.name : ''
output openAiId string = deployOpenAI ? openAi.id : ''
output openAiEndpoint string = deployOpenAI ? openAi.properties.endpoint : ''
output docIntelName string = deployDocIntel ? docIntel.name : ''
output docIntelId string = deployDocIntel ? docIntel.id : ''
output docIntelEndpoint string = deployDocIntel ? docIntel.properties.endpoint : ''
