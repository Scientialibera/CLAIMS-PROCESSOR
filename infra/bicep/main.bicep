targetScope = 'resourceGroup'

@description('Environment short name')
param envName string

@description('Primary location')
param location string = resourceGroup().location

@description('Optional secondary location for paired services')
param secondaryLocation string = location

@description('Name prefix for all resources')
param namePrefix string = 'claimsproc'

@description('Tags')
param tags object = {}

@description('Function runtime Python version')
param pythonVersion string = '3.11'

@description('Enable OpenAI account deployment')
param deployOpenAI bool = true

@description('Enable Document Intelligence account deployment')
param deployDocIntel bool = true

@description('OpenAI SKU')
param openAiSku string = 'S0'

@description('Doc Intelligence SKU')
param docIntelSku string = 'S0'

var suffix = toLower('${namePrefix}${envName}${uniqueString(resourceGroup().id)}')
var storageName = take(replace('${namePrefix}${envName}st${uniqueString(resourceGroup().id)}', '-', ''), 24)
var appInsightsName = '${namePrefix}-${envName}-appi'
var logAnalyticsName = '${namePrefix}-${envName}-law'
var sbName = take(replace('${namePrefix}-${envName}-sb-${uniqueString(resourceGroup().id)}', '-', ''), 50)
var cosmosName = take(replace('${namePrefix}-${envName}-cosmos-${uniqueString(resourceGroup().id)}', '-', ''), 44)
var searchName = take(replace('${namePrefix}-${envName}-srch-${uniqueString(resourceGroup().id)}', '-', ''), 60)
var planName = '${namePrefix}-${envName}-plan'
var functionAppName = '${namePrefix}-${envName}-func'
var keyVaultName = take(replace('${namePrefix}-${envName}-kv-${uniqueString(resourceGroup().id)}', '-', ''), 24)
var openAiName = take(replace('${namePrefix}-${envName}-aoai-${uniqueString(resourceGroup().id)}', '-', ''), 24)
var docIntelName = take(replace('${namePrefix}-${envName}-doci-${uniqueString(resourceGroup().id)}', '-', ''), 24)

module observability 'modules/observability.bicep' = {
  name: 'observability'
  params: {
    appInsightsName: appInsightsName
    logAnalyticsName: logAnalyticsName
    location: location
    tags: tags
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    storageAccountName: storageName
    location: location
    blobContainerName: 'claims'
    tags: tags
  }
}

module serviceBus 'modules/service-bus.bicep' = {
  name: 'servicebus'
  params: {
    namespaceName: sbName
    location: location
    readyQueueName: 'q-claim-ready'
    processingQueueName: 'q-claim-process'
    tags: tags
  }
}

module cosmos 'modules/cosmos.bicep' = {
  name: 'cosmos'
  params: {
    accountName: cosmosName
    location: location
    databaseName: 'claims'
    ledgerContainerName: 'processing_ledger'
    recordsContainerName: 'processed_records'
    tags: tags
  }
}

module search 'modules/search.bicep' = {
  name: 'search'
  params: {
    searchServiceName: searchName
    location: location
    sku: 'basic'
    tags: tags
  }
}

module keyVault 'modules/key-vault.bicep' = {
  name: 'keyvault'
  params: {
    keyVaultName: keyVaultName
    location: location
    tags: tags
  }
}

module cognitive 'modules/cognitive.bicep' = {
  name: 'cognitive'
  params: {
    location: location
    secondaryLocation: secondaryLocation
    deployOpenAI: deployOpenAI
    deployDocIntel: deployDocIntel
    openAiName: openAiName
    docIntelName: docIntelName
    openAiSku: openAiSku
    docIntelSku: docIntelSku
    tags: tags
  }
}

module functionApp 'modules/function-app.bicep' = {
  name: 'functionapp'
  params: {
    functionAppName: functionAppName
    planName: planName
    location: location
    storageAccountName: storage.outputs.storageAccountName
    appInsightsConnectionString: observability.outputs.appInsightsConnectionString
    pythonVersion: pythonVersion
    tags: tags
  }
}

output functionAppName string = functionApp.outputs.functionAppName
output functionPrincipalId string = functionApp.outputs.principalId
output serviceBusNamespaceName string = serviceBus.outputs.namespaceName
output serviceBusNamespaceFqdn string = serviceBus.outputs.namespaceFqdn
output readyQueueName string = serviceBus.outputs.readyQueueName
output processingQueueName string = serviceBus.outputs.processingQueueName
output storageAccountName string = storage.outputs.storageAccountName
output blobContainerName string = storage.outputs.blobContainerName
output blobAccountUrl string = storage.outputs.blobAccountUrl
output cosmosAccountName string = cosmos.outputs.accountName
output cosmosEndpoint string = cosmos.outputs.endpoint
output cosmosDatabaseName string = cosmos.outputs.databaseName
output cosmosLedgerContainer string = cosmos.outputs.ledgerContainerName
output cosmosRecordsContainer string = cosmos.outputs.recordsContainerName
output searchServiceName string = search.outputs.searchServiceName
output searchEndpoint string = search.outputs.searchEndpoint
output keyVaultName string = keyVault.outputs.keyVaultName
output openAiName string = cognitive.outputs.openAiName
output openAiEndpoint string = cognitive.outputs.openAiEndpoint
output docIntelName string = cognitive.outputs.docIntelName
output docIntelEndpoint string = cognitive.outputs.docIntelEndpoint
output appInsightsName string = observability.outputs.appInsightsName
output appInsightsConnectionString string = observability.outputs.appInsightsConnectionString
