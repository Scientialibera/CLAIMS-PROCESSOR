param(
    [string]$ConfigPath = "deploy/deploy.config.toml"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

function Write-Step { param([string]$Message) Write-Host "[deploy-infra] $Message" }

function Get-Config {
    param([string]$Path)
    if (-not (Test-Path $Path)) { throw "Config file not found: $Path" }
    $json = python -c "import json, pathlib, tomllib; p=pathlib.Path(r'$Path'); print(json.dumps(tomllib.loads(p.read_text(encoding='utf-8'))))"
    if ($LASTEXITCODE -ne 0) { throw "Failed to parse config file: $Path" }
    return $json | ConvertFrom-Json
}

function Select-Value {
    param([string]$Configured, [string]$Default)
    if ([string]::IsNullOrWhiteSpace($Configured)) { return $Default }
    return $Configured
}

function Normalize-StorageAccountName {
    param([string]$Value)
    $normalized = ($Value.ToLower() -replace "[^a-z0-9]", "")
    if ([string]::IsNullOrWhiteSpace($normalized)) { throw "Invalid naming prefix for storage account." }
    if ($normalized.Length -lt 3) { $normalized = $normalized + "123" }
    if ($normalized.Length -gt 22) { $normalized = $normalized.Substring(0, 22) }
    return "st$normalized"
}

function Normalize-ServiceBusNamespaceName {
    param([string]$Value)
    $normalized = ($Value.ToLower() -replace "[^a-z0-9-]", "-")
    $normalized = ($normalized -replace "^-+", "") -replace "-+$", ""
    if ([string]::IsNullOrWhiteSpace($normalized)) { throw "Invalid naming prefix for service bus namespace." }
    if ($normalized.Length -gt 38) { $normalized = $normalized.Substring(0, 38) }
    return "sbns-$normalized"
}

function Normalize-CosmosName {
    param([string]$Value)
    $normalized = ($Value.ToLower() -replace "[^a-z0-9-]", "")
    if ([string]::IsNullOrWhiteSpace($normalized)) { throw "Invalid naming prefix for cosmos account." }
    if ($normalized.Length -gt 44) { $normalized = $normalized.Substring(0, 44) }
    return "cosmos-$normalized"
}

function Normalize-SearchName {
    param([string]$Value)
    $normalized = ($Value.ToLower() -replace "[^a-z0-9-]", "")
    if ([string]::IsNullOrWhiteSpace($normalized)) { throw "Invalid naming prefix for search service." }
    if ($normalized.Length -gt 53) { $normalized = $normalized.Substring(0, 53) }
    return "srch-$normalized"
}

function Normalize-CogName {
    param([string]$Prefix, [string]$Value)
    $normalized = ($Value.ToLower() -replace "[^a-z0-9-]", "")
    if ([string]::IsNullOrWhiteSpace($normalized)) { throw "Invalid naming prefix for cognitive account." }
    if ($normalized.Length -gt 18) { $normalized = $normalized.Substring(0, 18) }
    return "$Prefix-$normalized"
}

function Ensure-RoleAssignment {
    param(
        [string]$PrincipalId,
        [string]$Scope,
        [string]$Role,
        [string]$PrincipalType = "ServicePrincipal"
    )
    $count = az role assignment list `
      --assignee-object-id $PrincipalId `
      --scope $Scope `
      --query "[?roleDefinitionName=='$Role'] | length(@)" `
      -o tsv
    if ($LASTEXITCODE -ne 0) { throw "Failed to query role assignments for '$Role'." }
    if ($count -eq "0") {
      Write-Step "Assigning role '$Role' on scope '$Scope'."
      az role assignment create `
        --assignee-object-id $PrincipalId `
        --assignee-principal-type $PrincipalType `
        --role $Role `
        --scope $Scope | Out-Null
    }
}

$config = Get-Config -Path $ConfigPath

$subscriptionId = $config.azure.subscription_id
if ([string]::IsNullOrWhiteSpace($subscriptionId)) { $subscriptionId = az account show --query id -o tsv }
if ([string]::IsNullOrWhiteSpace($subscriptionId)) { throw "No Azure subscription id found. Set azure.subscription_id or run az login." }

$prefix = $config.naming.prefix.ToLower()
$location = Select-Value $config.azure.location "eastus2"
$resourceGroup = Select-Value $config.azure.resource_group_name "rg-$prefix"
$functionAppName = Select-Value $config.naming.function_app_name "func-$prefix"
$storageAccount = Select-Value $config.naming.storage_account_name (Normalize-StorageAccountName -Value $prefix)
$serviceBusNamespace = Select-Value $config.naming.servicebus_namespace_name (Normalize-ServiceBusNamespaceName -Value $prefix)
$cosmosAccount = Select-Value $config.naming.cosmos_account_name (Normalize-CosmosName -Value $prefix)
$searchService = Select-Value $config.naming.search_service_name (Normalize-SearchName -Value $prefix)
$openAiAccount = Select-Value $config.naming.openai_account_name (Normalize-CogName -Prefix "aoai" -Value $prefix)
$docIntelAccount = Select-Value $config.naming.docintel_account_name (Normalize-CogName -Prefix "doci" -Value $prefix)

$claimsContainer = $config.storage.claims_container_name
$promptsContainer = $config.storage.prompts_container_name
$functionDefsContainer = $config.storage.function_definitions_container_name
$schemasContainer = $config.storage.schemas_container_name
$readyQueue = $config.queues.ready_queue_name
$processingQueue = $config.queues.processing_queue_name

$cosmosDb = $config.cosmos.database_name
$ledgerContainer = $config.cosmos.ledger_container_name
$recordsContainer = $config.cosmos.records_container_name

$deploySearchService = [bool]$config.search.deploy_search_service
$searchSku = $config.search.sku
$searchIndex = $config.search.index_name

$deployOpenAI = [bool]$config.openai.deploy_openai_resources
$deployDocIntel = [bool]$config.docintel.deploy_docintel_resources

Write-Step "Using subscription: $subscriptionId"
az account set --subscription $subscriptionId

$executorObjectId = az ad signed-in-user show --query id -o tsv
if ([string]::IsNullOrWhiteSpace($executorObjectId)) { throw "Could not resolve signed-in user object id." }

Write-Step "Ensuring resource group '$resourceGroup'."
$rgExists = az group exists --name $resourceGroup -o tsv
if ($rgExists -ne "true") { az group create --name $resourceGroup --location $location | Out-Null }
$rgScope = az group show --name $resourceGroup --query id -o tsv
Ensure-RoleAssignment -PrincipalId $executorObjectId -PrincipalType User -Scope $rgScope -Role "Contributor"

Write-Step "Ensuring storage account '$storageAccount'."
$storageExists = az storage account list --resource-group $resourceGroup --query "[?name=='$storageAccount'] | length(@)" -o tsv
if ($storageExists -eq "0") {
    az storage account create `
      --resource-group $resourceGroup `
      --name $storageAccount `
      --location $location `
      --sku Standard_LRS `
      --kind StorageV2 `
      --min-tls-version TLS1_2 `
      --allow-blob-public-access false | Out-Null
}
$storageScope = az storage account show --resource-group $resourceGroup --name $storageAccount --query id -o tsv
Ensure-RoleAssignment -PrincipalId $executorObjectId -PrincipalType User -Scope $storageScope -Role "Storage Blob Data Owner"
foreach ($container in @($claimsContainer, $promptsContainer, $functionDefsContainer, $schemasContainer)) {
    $exists = az storage container exists --account-name $storageAccount --name $container --auth-mode login --query exists -o tsv
    if ($exists -ne "true") {
        az storage container create --account-name $storageAccount --name $container --auth-mode login | Out-Null
    }
}

Write-Step "Ensuring Service Bus namespace '$serviceBusNamespace'."
$sbExists = az servicebus namespace list --resource-group $resourceGroup --query "[?name=='$serviceBusNamespace'] | length(@)" -o tsv
if ($sbExists -eq "0") {
    az servicebus namespace create --resource-group $resourceGroup --name $serviceBusNamespace --location $location --sku Standard | Out-Null
}

$readyQueueExists = az servicebus queue list --resource-group $resourceGroup --namespace-name $serviceBusNamespace --query "[?name=='$readyQueue'] | length(@)" -o tsv
if ($readyQueueExists -eq "0") {
    az servicebus queue create --resource-group $resourceGroup --namespace-name $serviceBusNamespace --name $readyQueue --enable-session false | Out-Null
}
$procQueueExists = az servicebus queue list --resource-group $resourceGroup --namespace-name $serviceBusNamespace --query "[?name=='$processingQueue'] | length(@)" -o tsv
if ($procQueueExists -eq "0") {
    az servicebus queue create --resource-group $resourceGroup --namespace-name $serviceBusNamespace --name $processingQueue --enable-session true | Out-Null
}

Write-Step "Ensuring Cosmos DB account '$cosmosAccount'."
$cosmosExists = az cosmosdb list --resource-group $resourceGroup --query "[?name=='$cosmosAccount'] | length(@)" -o tsv
if ($cosmosExists -eq "0") {
    az cosmosdb create --resource-group $resourceGroup --name $cosmosAccount --locations regionName=$location failoverPriority=0 isZoneRedundant=false | Out-Null
}
az cosmosdb sql database create --resource-group $resourceGroup --account-name $cosmosAccount --name $cosmosDb | Out-Null
az cosmosdb sql container create `
  --resource-group $resourceGroup `
  --account-name $cosmosAccount `
  --database-name $cosmosDb `
  --name $ledgerContainer `
  --partition-key-path "/claim_id" `
  --throughput 400 | Out-Null
az cosmosdb sql container create `
  --resource-group $resourceGroup `
  --account-name $cosmosAccount `
  --database-name $cosmosDb `
  --name $recordsContainer `
  --partition-key-path "/claim_id" `
  --throughput 400 | Out-Null

if ($deploySearchService) {
    Write-Step "Ensuring AI Search service '$searchService'."
    $searchExists = az search service list --resource-group $resourceGroup --query "[?name=='$searchService'] | length(@)" -o tsv
    if ($searchExists -eq "0") {
        az search service create --resource-group $resourceGroup --name $searchService --sku $searchSku --partition-count 1 --replica-count 1 | Out-Null
    }
} else {
    $searchExists = az search service list --resource-group $resourceGroup --query "[?name=='$searchService'] | length(@)" -o tsv
    if ($searchExists -eq "0") { throw "Search service '$searchService' not found and deploy_search_service=false." }
}

if ($deployOpenAI) {
    Write-Step "Ensuring Azure OpenAI account '$openAiAccount' (standalone OpenAI kind)."
    $aoaiExists = az cognitiveservices account list --resource-group $resourceGroup --query "[?name=='$openAiAccount'] | length(@)" -o tsv
    if ($aoaiExists -eq "0") {
        az cognitiveservices account create --name $openAiAccount --resource-group $resourceGroup --kind OpenAI --sku S0 --location $location --custom-domain $openAiAccount | Out-Null
    } else {
        $existingDomain = az cognitiveservices account show --name $openAiAccount --resource-group $resourceGroup --query "properties.customSubDomainName" -o tsv
        if ([string]::IsNullOrWhiteSpace($existingDomain)) {
            Write-Step "Adding custom subdomain to existing OpenAI account (required for token auth)."
            az cognitiveservices account update --name $openAiAccount --resource-group $resourceGroup --custom-domain $openAiAccount | Out-Null
        }
    }
} elseif ([string]::IsNullOrWhiteSpace($config.naming.openai_account_name)) {
    throw "naming.openai_account_name is required when openai.deploy_openai_resources=false."
}

if ($deployDocIntel) {
    Write-Step "Ensuring Document Intelligence account '$docIntelAccount' (AIServices kind)."
    $dociExists = az cognitiveservices account list --resource-group $resourceGroup --query "[?name=='$docIntelAccount'] | length(@)" -o tsv
    if ($dociExists -eq "0") {
        az cognitiveservices account create --name $docIntelAccount --resource-group $resourceGroup --kind AIServices --sku $config.docintel.sku_name --location $location --custom-domain $docIntelAccount | Out-Null
    } else {
        $existingDomain = az cognitiveservices account show --name $docIntelAccount --resource-group $resourceGroup --query "properties.customSubDomainName" -o tsv
        if ([string]::IsNullOrWhiteSpace($existingDomain)) {
            Write-Step "Adding custom subdomain to existing Doc Intelligence account (required for token auth)."
            az cognitiveservices account update --name $docIntelAccount --resource-group $resourceGroup --custom-domain $docIntelAccount | Out-Null
        }
    }
} elseif ([string]::IsNullOrWhiteSpace($config.naming.docintel_account_name)) {
    throw "naming.docintel_account_name is required when docintel.deploy_docintel_resources=false."
}

Write-Step "Ensuring Function App '$functionAppName' on Flex Consumption."
$funcExists = az functionapp list --resource-group $resourceGroup --query "[?name=='$functionAppName'] | length(@)" -o tsv
if ($funcExists -eq "0") {
    az functionapp create `
      --resource-group $resourceGroup `
      --name $functionAppName `
      --storage-account $storageAccount `
      --flexconsumption-location $location `
      --runtime python `
      --runtime-version 3.11 `
      --functions-version 4 | Out-Null
}

az functionapp identity assign --resource-group $resourceGroup --name $functionAppName --identities [system] | Out-Null
$functionPrincipalId = az functionapp identity show --resource-group $resourceGroup --name $functionAppName --query principalId -o tsv
if ([string]::IsNullOrWhiteSpace($functionPrincipalId)) { throw "Could not resolve function managed identity principal id." }

$readyQueueScope = az servicebus queue show --resource-group $resourceGroup --namespace-name $serviceBusNamespace --name $readyQueue --query id -o tsv
$procQueueScope = az servicebus queue show --resource-group $resourceGroup --namespace-name $serviceBusNamespace --name $processingQueue --query id -o tsv
$searchScope = az search service show --resource-group $resourceGroup --name $searchService --query id -o tsv

Ensure-RoleAssignment -PrincipalId $functionPrincipalId -Scope $readyQueueScope -Role "Azure Service Bus Data Receiver"
Ensure-RoleAssignment -PrincipalId $functionPrincipalId -Scope $procQueueScope -Role "Azure Service Bus Data Sender"
Ensure-RoleAssignment -PrincipalId $functionPrincipalId -Scope $procQueueScope -Role "Azure Service Bus Data Receiver"
Ensure-RoleAssignment -PrincipalId $functionPrincipalId -Scope $storageScope -Role "Storage Blob Data Contributor"
Ensure-RoleAssignment -PrincipalId $functionPrincipalId -Scope $searchScope -Role "Search Index Data Contributor"

$cosmosDataContributor = az cosmosdb sql role definition list --account-name $cosmosAccount --resource-group $resourceGroup --query "[?roleName=='Cosmos DB Built-in Data Contributor'].id | [0]" -o tsv
$existingCosmosAssignment = az cosmosdb sql role assignment list --account-name $cosmosAccount --resource-group $resourceGroup --query "[?principalId=='$functionPrincipalId' && roleDefinitionId=='$cosmosDataContributor'] | length(@)" -o tsv
if ($existingCosmosAssignment -eq "0") {
    az cosmosdb sql role assignment create --account-name $cosmosAccount --resource-group $resourceGroup --scope "/" --principal-id $functionPrincipalId --role-definition-id $cosmosDataContributor | Out-Null
}

$openAiEndpoint = az cognitiveservices account show --resource-group $resourceGroup --name $openAiAccount --query properties.endpoint -o tsv
if (-not [string]::IsNullOrWhiteSpace($openAiEndpoint)) {
    $openAiScope = az cognitiveservices account show --resource-group $resourceGroup --name $openAiAccount --query id -o tsv
    Ensure-RoleAssignment -PrincipalId $functionPrincipalId -Scope $openAiScope -Role "Cognitive Services User"

    foreach ($deployment in @(
      @{ name=$config.openai.deployment_segment_name; model=$config.openai.model_segment_name; version=$config.openai.model_segment_version },
      @{ name=$config.openai.deployment_classify_name; model=$config.openai.model_classify_name; version=$config.openai.model_classify_version },
      @{ name=$config.openai.deployment_extract_name; model=$config.openai.model_extract_name; version=$config.openai.model_extract_version },
      @{ name=$config.openai.deployment_embedding_name; model=$config.openai.model_embedding_name; version=$config.openai.model_embedding_version }
    )) {
      $exists = az cognitiveservices account deployment list --name $openAiAccount --resource-group $resourceGroup --query "[?name=='$($deployment.name)'] | length(@)" -o tsv
      if ($exists -eq "0") {
        az cognitiveservices account deployment create `
          --name $openAiAccount `
          --resource-group $resourceGroup `
          --deployment-name $deployment.name `
          --model-format OpenAI `
          --model-name $deployment.model `
          --model-version $deployment.version `
          --sku-name $config.openai.deployment_sku_name `
          --sku-capacity $config.openai.capacity | Out-Null
      }
    }
}

$docIntelEndpoint = az cognitiveservices account show --resource-group $resourceGroup --name $docIntelAccount --query properties.endpoint -o tsv
if (-not [string]::IsNullOrWhiteSpace($docIntelEndpoint)) {
    $docScope = az cognitiveservices account show --resource-group $resourceGroup --name $docIntelAccount --query id -o tsv
    Ensure-RoleAssignment -PrincipalId $functionPrincipalId -Scope $docScope -Role "Cognitive Services User"
}

$blobAccountUrl = az storage account show --resource-group $resourceGroup --name $storageAccount --query "primaryEndpoints.blob" -o tsv
$searchEndpoint = "https://$searchService.search.windows.net"
$serviceBusFqdn = "$serviceBusNamespace.servicebus.windows.net"
$cosmosEndpoint = az cosmosdb show --resource-group $resourceGroup --name $cosmosAccount --query documentEndpoint -o tsv

$appSettings = @(
  "SERVICEBUS_CONNECTION__fullyQualifiedNamespace=$serviceBusFqdn",
  "SERVICEBUS_READY_QUEUE_NAME=$readyQueue",
  "SERVICEBUS_PROCESSING_QUEUE_NAME=$processingQueue",
  "SERVICEBUS_NAMESPACE_FQDN=$serviceBusFqdn",
  "BLOB_ACCOUNT_URL=$($blobAccountUrl.TrimEnd('/'))",
  "BLOB_CONTAINER=$claimsContainer",
  "BLOB_CLAIMS_PREFIX=",
  "COSMOS_ENDPOINT=$cosmosEndpoint",
  "COSMOS_DATABASE=$cosmosDb",
  "COSMOS_LEDGER_CONTAINER=$ledgerContainer",
  "COSMOS_RECORDS_CONTAINER=$recordsContainer",
  "DOCINTEL_ENDPOINT=$docIntelEndpoint",
  "AOAI_ENDPOINT=$openAiEndpoint",
  "AOAI_API_VERSION=$($config.openai.api_version)",
  "AOAI_DEPLOYMENT_SEGMENT=$($config.openai.deployment_segment_name)",
  "AOAI_DEPLOYMENT_CLASSIFY=$($config.openai.deployment_classify_name)",
  "AOAI_DEPLOYMENT_EXTRACT=$($config.openai.deployment_extract_name)",
  "AOAI_DEPLOYMENT_EMBEDDING=$($config.openai.deployment_embedding_name)",
  "SEARCH_ENDPOINT=$searchEndpoint",
  "SEARCH_INDEX=$searchIndex",
  "SEARCH_USE_EMBEDDINGS=$($config.app_settings.search_use_embeddings.ToString().ToLower())",
  "SEARCH_EMBEDDING_DIMENSIONS=$($config.app_settings.search_embedding_dimensions)",
  "PIPELINE_VERSION=$($config.app_settings.pipeline_version)",
  "ACTIVE_EXTRACTION_SCHEMA=$($config.app_settings.active_extraction_schema)",
  "ACTIVE_CLASSIFICATION_SCHEMA=$($config.app_settings.active_classification_schema)",
  "ACTIVE_SEGMENTATION_FUNCTION=$($config.app_settings.active_segmentation_function)",
  "ACTIVE_EXTRACTION_FUNCTION=$($config.app_settings.active_extraction_function)",
  "ACTIVE_CLASSIFICATION_FUNCTION=$($config.app_settings.active_classification_function)",
  "ACTIVE_MODEL_PROFILE=$($config.app_settings.active_model_profile)",
  "MAX_INDEX_CHUNK_TOKENS=$($config.app_settings.max_index_chunk_tokens)"
)
az functionapp config appsettings set --resource-group $resourceGroup --name $functionAppName --settings $appSettings | Out-Null

Write-Step "Infrastructure deployment complete."
Write-Output ""
Write-Output "Resource group: $resourceGroup"
Write-Output "Storage account: $storageAccount"
Write-Output "Service Bus namespace: $serviceBusNamespace"
Write-Output "Cosmos account: $cosmosAccount"
Write-Output "Search service: $searchService"
Write-Output "Function app: $functionAppName"
