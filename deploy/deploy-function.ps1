param(
    [string]$ConfigPath = "deploy/deploy.config.toml"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

function Write-Step { param([string]$Message) Write-Host "[deploy-function] $Message" }

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

function Ensure-RoleAssignment {
    param(
        [string]$PrincipalId,
        [string]$Scope,
        [string]$Role,
        [string]$PrincipalType = "User"
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

function Upload-BlobFromFile {
    param(
        [string]$StorageAccount,
        [string]$Container,
        [string]$BlobName,
        [string]$FilePath
    )
    if (-not (Test-Path $FilePath)) { throw "Seed source file not found: $FilePath" }
    az storage blob upload `
      --auth-mode login `
      --account-name $StorageAccount `
      --container-name $Container `
      --name $BlobName `
      --file $FilePath `
      --overwrite true | Out-Null
}

if (-not (Get-Command func -ErrorAction SilentlyContinue)) {
    throw "Azure Functions Core Tools (func) is required."
}

$config = Get-Config -Path $ConfigPath
$subscriptionId = $config.azure.subscription_id
if ([string]::IsNullOrWhiteSpace($subscriptionId)) { $subscriptionId = az account show --query id -o tsv }
if ([string]::IsNullOrWhiteSpace($subscriptionId)) { throw "No Azure subscription id found. Set azure.subscription_id or run az login." }
az account set --subscription $subscriptionId

$prefix = $config.naming.prefix.ToLower()
$resourceGroup = Select-Value $config.azure.resource_group_name "rg-$prefix"
$functionAppName = Select-Value $config.naming.function_app_name "func-$prefix"
$storageAccount = Select-Value $config.naming.storage_account_name (Normalize-StorageAccountName -Value $prefix)
$promptsContainer = $config.storage.prompts_container_name
$functionDefsContainer = $config.storage.function_definitions_container_name
$schemasContainer = $config.storage.schemas_container_name

if ([string]::IsNullOrWhiteSpace($config.naming.function_app_name)) {
    $detectedFunction = az functionapp list --resource-group $resourceGroup --query "[0].name" -o tsv 2>$null
    if (-not [string]::IsNullOrWhiteSpace($detectedFunction)) { $functionAppName = $detectedFunction }
}
if ([string]::IsNullOrWhiteSpace($config.naming.storage_account_name)) {
    $detectedStorage = az storage account list --resource-group $resourceGroup --query "[0].name" -o tsv 2>$null
    if (-not [string]::IsNullOrWhiteSpace($detectedStorage)) { $storageAccount = $detectedStorage }
}

if ([string]::IsNullOrWhiteSpace($functionAppName)) { throw "Function app name could not be resolved." }
if ([string]::IsNullOrWhiteSpace($storageAccount)) { throw "Storage account name could not be resolved." }

Write-Step "Publishing to $functionAppName ..."
func azure functionapp publish $functionAppName --python

Write-Step "Ensuring executor blob role for seeding."
$executorObjectId = az ad signed-in-user show --query id -o tsv
$storageScope = az storage account show --resource-group $resourceGroup --name $storageAccount --query id -o tsv
Ensure-RoleAssignment -PrincipalId $executorObjectId -Scope $storageScope -Role "Storage Blob Data Owner"

Write-Step "Seeding prompts/function definitions/schemas."
Upload-BlobFromFile -StorageAccount $storageAccount -Container $promptsContainer -BlobName $config.seed.segmentation_prompt_blob_name -FilePath "src/prompts/segmentation/segment_v1.txt"
Upload-BlobFromFile -StorageAccount $storageAccount -Container $promptsContainer -BlobName $config.seed.classification_prompt_blob_name -FilePath "src/prompts/classification/classify_v1.txt"
Upload-BlobFromFile -StorageAccount $storageAccount -Container $promptsContainer -BlobName $config.seed.extraction_prompt_blob_name -FilePath "src/prompts/extraction/extract_v1.txt"
Upload-BlobFromFile -StorageAccount $storageAccount -Container $promptsContainer -BlobName $config.seed.photo_summary_prompt_blob_name -FilePath "src/prompts/extraction/photo_summary_v1.txt"
Upload-BlobFromFile -StorageAccount $storageAccount -Container $functionDefsContainer -BlobName $config.seed.segmentation_fn_blob_name -FilePath "src/function_definitions/segmentation/segment_docs_v1.json"
Upload-BlobFromFile -StorageAccount $storageAccount -Container $functionDefsContainer -BlobName $config.seed.extraction_fn_blob_name -FilePath "src/function_definitions/extraction/extract_fields_v1.json"
Upload-BlobFromFile -StorageAccount $storageAccount -Container $functionDefsContainer -BlobName $config.seed.classification_fn_blob_name -FilePath "src/function_definitions/classification/classify_doc_v1.json"
Upload-BlobFromFile -StorageAccount $storageAccount -Container $schemasContainer -BlobName $config.seed.extraction_schema_blob_name -FilePath "src/schemas/extraction/claim_core_v1.json"
Upload-BlobFromFile -StorageAccount $storageAccount -Container $schemasContainer -BlobName $config.seed.classification_schema_blob_name -FilePath "src/schemas/classification/doc_types_v1.json"

Write-Step "Ensuring search index exists."
$searchService = Select-Value $config.naming.search_service_name ""
if ([string]::IsNullOrWhiteSpace($searchService)) {
    $searchService = az search service list --resource-group $resourceGroup --query "[0].name" -o tsv
}
if ([string]::IsNullOrWhiteSpace($searchService)) { throw "Search service name could not be resolved." }
$indexName = $config.search.index_name
$indexExists = az search index list --resource-group $resourceGroup --service-name $searchService --query "[?name=='$indexName'] | length(@)" -o tsv

$fields = @(
  @{ name='id'; type='Edm.String'; key=$true; searchable=$false; filterable=$true; sortable=$false; facetable=$false; retrievable=$true },
  @{ name='claim_id'; type='Edm.String'; searchable=$false; filterable=$true; sortable=$true; facetable=$true; retrievable=$true },
  @{ name='document_id'; type='Edm.String'; searchable=$false; filterable=$true; sortable=$false; facetable=$false; retrievable=$true },
  @{ name='chunk_id'; type='Edm.String'; searchable=$false; filterable=$true; sortable=$false; facetable=$false; retrievable=$true },
  @{ name='document_name'; type='Edm.String'; searchable=$true; filterable=$true; sortable=$true; facetable=$false; retrievable=$true },
  @{ name='content'; type='Edm.String'; searchable=$true; filterable=$false; sortable=$false; facetable=$false; retrievable=$true },
  @{ name='document_summary'; type='Edm.String'; searchable=$true; filterable=$false; sortable=$false; facetable=$false; retrievable=$true },
  @{ name='created_at'; type='Edm.String'; searchable=$false; filterable=$true; sortable=$true; facetable=$false; retrievable=$true }
)
if ([bool]$config.app_settings.search_use_embeddings) {
    $fields += @{ name='content_vector'; type='Collection(Edm.Single)'; searchable=$true; retrievable=$false; dimensions=[int]$config.app_settings.search_embedding_dimensions; vectorSearchProfile='claims-vector-profile' }
}

$indexSchema = @{
  name = $indexName
  fields = $fields
}
if ([bool]$config.app_settings.search_use_embeddings) {
    $indexSchema.vectorSearch = @{
      algorithms = @(@{ name='claims-hnsw'; kind='hnsw' })
      profiles = @(@{ name='claims-vector-profile'; algorithm='claims-hnsw' })
    }
}

$schemaJson = $indexSchema | ConvertTo-Json -Depth 20
$adminKey = az search admin-key show --resource-group $resourceGroup --service-name $searchService --query primaryKey -o tsv
$headers = @{ 'Content-Type'='application/json'; 'api-key'=$adminKey }
$indexUri = "https://$searchService.search.windows.net/indexes/$indexName`?api-version=2023-11-01"
Invoke-RestMethod -Method Put -Uri $indexUri -Headers $headers -Body $schemaJson | Out-Null

Write-Step "Syncing trigger metadata."
az rest --method post --uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Web/sites/$functionAppName/syncfunctiontriggers?api-version=2025-05-01" | Out-Null

Write-Step "Function deployment complete."
