param(
  [Parameter(Mandatory=$true)][string]$SubscriptionId,
  [Parameter(Mandatory=$true)][string]$ResourceGroup,
  [string]$AoaiDeploymentSegment = 'gpt-4.1-mini',
  [string]$AoaiDeploymentClassify = 'gpt-4.1-mini',
  [string]$AoaiDeploymentExtract = 'gpt-4.1'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path .deploy/outputs.json)) {
  throw "Missing .deploy/outputs.json. Run 00_deploy_infra.ps1 first."
}

az account set --subscription $SubscriptionId | Out-Null

$o = Get-Content .deploy/outputs.json | ConvertFrom-Json
$functionAppName = $o.functionAppName.value

$appSettings = @{
  "SERVICEBUS_CONNECTION__fullyQualifiedNamespace" = $o.serviceBusNamespaceFqdn.value
  "SERVICEBUS_READY_QUEUE_NAME" = $o.readyQueueName.value
  "SERVICEBUS_PROCESSING_QUEUE_NAME" = $o.processingQueueName.value
  "SERVICEBUS_NAMESPACE_FQDN" = $o.serviceBusNamespaceFqdn.value
  "BLOB_ACCOUNT_URL" = $o.blobAccountUrl.value.TrimEnd('/')
  "BLOB_CONTAINER" = $o.blobContainerName.value
  "BLOB_CLAIMS_PREFIX" = ""
  "COSMOS_ENDPOINT" = $o.cosmosEndpoint.value
  "COSMOS_DATABASE" = $o.cosmosDatabaseName.value
  "COSMOS_LEDGER_CONTAINER" = $o.cosmosLedgerContainer.value
  "COSMOS_RECORDS_CONTAINER" = $o.cosmosRecordsContainer.value
  "SEARCH_ENDPOINT" = $o.searchEndpoint.value
  "SEARCH_INDEX" = "claims-index"
  "PIPELINE_VERSION" = "v1"
  "DOCINTEL_ENDPOINT" = $o.docIntelEndpoint.value
  "AOAI_ENDPOINT" = $o.openAiEndpoint.value
  "AOAI_API_VERSION" = "2024-06-01"
  "AOAI_DEPLOYMENT_SEGMENT" = $AoaiDeploymentSegment
  "AOAI_DEPLOYMENT_CLASSIFY" = $AoaiDeploymentClassify
  "AOAI_DEPLOYMENT_EXTRACT" = $AoaiDeploymentExtract
  "ACTIVE_EXTRACTION_SCHEMA" = "claim_core_v1"
  "ACTIVE_CLASSIFICATION_SCHEMA" = "doc_types_v1"
  "ACTIVE_MODEL_PROFILE" = "default"
}

$settingsArgs = @()
foreach ($kv in $appSettings.GetEnumerator()) {
  if ($null -ne $kv.Value -and "$($kv.Value)" -ne "") {
    $settingsArgs += "$($kv.Key)=$($kv.Value)"
  }
}

az functionapp config appsettings set --resource-group $ResourceGroup --name $functionAppName --settings $settingsArgs | Out-Null
Write-Host "Function app settings applied for $functionAppName"
