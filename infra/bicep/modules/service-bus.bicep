param namespaceName string
param location string
param readyQueueName string
param processingQueueName string
param tags object = {}

resource sb 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: namespaceName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

resource readyQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  name: '${sb.name}/${readyQueueName}'
  properties: {
    requiresSession: false
    deadLetteringOnMessageExpiration: true
    lockDuration: 'PT1M'
    maxDeliveryCount: 10
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    requiresDuplicateDetection: false
  }
}

resource processingQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  name: '${sb.name}/${processingQueueName}'
  properties: {
    requiresSession: true
    deadLetteringOnMessageExpiration: true
    lockDuration: 'PT2M'
    maxDeliveryCount: 10
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    requiresDuplicateDetection: false
  }
}

output namespaceName string = sb.name
output namespaceId string = sb.id
output namespaceFqdn string = '${sb.name}.servicebus.windows.net'
output readyQueueName string = readyQueue.name
output processingQueueName string = processingQueue.name
