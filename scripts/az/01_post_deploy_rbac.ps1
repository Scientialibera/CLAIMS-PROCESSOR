param(
  [Parameter(Mandatory=$true)][string]$SubscriptionId,
  [Parameter(Mandatory=$true)][string]$ResourceGroup
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path .deploy/outputs.json)) {
  throw "Missing .deploy/outputs.json. Run 00_deploy_infra.ps1 first."
}

az account set --subscription $SubscriptionId | Out-Null

$o = Get-Content .deploy/outputs.json | ConvertFrom-Json
$functionPrincipalId = $o.functionPrincipalId.value

$storageAccountName = $o.storageAccountName.value
$serviceBusNamespace = $o.serviceBusNamespaceName.value
$cosmosAccountName = $o.cosmosAccountName.value
$searchServiceName = $o.searchServiceName.value
$keyVaultName = $o.keyVaultName.value
$openAiName = $o.openAiName.value
$docIntelName = $o.docIntelName.value

$storageScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Storage/storageAccounts/$storageAccountName"
$serviceBusScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ServiceBus/namespaces/$serviceBusNamespace"
$searchScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Search/searchServices/$searchServiceName"
$keyVaultScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.KeyVault/vaults/$keyVaultName"
$openAiScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.CognitiveServices/accounts/$openAiName"
$docIntelScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.CognitiveServices/accounts/$docIntelName"

Write-Host "Assigning RBAC to Function managed identity: $functionPrincipalId"

function Ensure-RoleAssignment {
  param(
    [string]$AssigneeObjectId,
    [string]$RoleName,
    [string]$Scope
  )

  $existing = az role assignment list `
    --assignee-object-id $AssigneeObjectId `
    --scope $Scope `
    --query "[?roleDefinitionName=='$RoleName'] | length(@)" -o tsv

  if ($existing -eq "0") {
    az role assignment create --assignee-object-id $AssigneeObjectId --assignee-principal-type ServicePrincipal --role $RoleName --scope $Scope | Out-Null
    Write-Host "Assigned role '$RoleName' on '$Scope'"
  } else {
    Write-Host "Role '$RoleName' already assigned on '$Scope'"
  }
}

Ensure-RoleAssignment -AssigneeObjectId $functionPrincipalId -RoleName "Storage Blob Data Contributor" -Scope $storageScope
Ensure-RoleAssignment -AssigneeObjectId $functionPrincipalId -RoleName "Azure Service Bus Data Sender" -Scope $serviceBusScope
Ensure-RoleAssignment -AssigneeObjectId $functionPrincipalId -RoleName "Azure Service Bus Data Receiver" -Scope $serviceBusScope
Ensure-RoleAssignment -AssigneeObjectId $functionPrincipalId -RoleName "Search Index Data Contributor" -Scope $searchScope
Ensure-RoleAssignment -AssigneeObjectId $functionPrincipalId -RoleName "Key Vault Secrets User" -Scope $keyVaultScope

if ($openAiName) {
  Ensure-RoleAssignment -AssigneeObjectId $functionPrincipalId -RoleName "Cognitive Services User" -Scope $openAiScope
}
if ($docIntelName) {
  Ensure-RoleAssignment -AssigneeObjectId $functionPrincipalId -RoleName "Cognitive Services User" -Scope $docIntelScope
}

# Cosmos SQL data-plane role assignment
$cosmosDataContributor = az cosmosdb sql role definition list --account-name $cosmosAccountName --resource-group $ResourceGroup --query "[?roleName=='Cosmos DB Built-in Data Contributor'].id | [0]" -o tsv
if (-not $cosmosDataContributor) {
  throw "Could not resolve Cosmos DB Built-in Data Contributor role definition."
}
$existingCosmos = az cosmosdb sql role assignment list --account-name $cosmosAccountName --resource-group $ResourceGroup --query "[?principalId=='$functionPrincipalId' && roleDefinitionId=='$cosmosDataContributor'] | length(@)" -o tsv
if ($existingCosmos -eq "0") {
  az cosmosdb sql role assignment create --account-name $cosmosAccountName --resource-group $ResourceGroup --scope "/" --principal-id $functionPrincipalId --role-definition-id $cosmosDataContributor | Out-Null
  Write-Host "Assigned Cosmos DB Built-in Data Contributor"
} else {
  Write-Host "Cosmos DB Built-in Data Contributor already assigned"
}

Write-Host "RBAC assignments completed."
