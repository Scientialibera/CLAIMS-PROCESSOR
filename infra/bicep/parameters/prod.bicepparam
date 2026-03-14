using '../main.bicep'

param envName = 'prod'
param location = 'eastus2'
param secondaryLocation = 'eastus'
param namePrefix = 'claimsproc'
param tags = {
  environment: 'prod'
  system: 'claims-processor'
  owner: 'argano'
}
param deployOpenAI = true
param deployDocIntel = true
param openAiSku = 'S0'
param docIntelSku = 'S0'
