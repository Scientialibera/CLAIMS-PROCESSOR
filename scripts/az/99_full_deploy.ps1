param(
  [Parameter(Mandatory=$true)][string]$SubscriptionId,
  [Parameter(Mandatory=$true)][string]$ResourceGroup,
  [Parameter(Mandatory=$true)][ValidateSet('dev','prod')][string]$Environment,
  [string]$Location = 'eastus2',
  [string]$AoaiDeploymentSegment = 'gpt-4.1-mini',
  [string]$AoaiDeploymentClassify = 'gpt-4.1-mini',
  [string]$AoaiDeploymentExtract = 'gpt-4.1'
)

$ErrorActionPreference = 'Stop'

./scripts/az/00_deploy_infra.ps1 -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -Environment $Environment -Location $Location
./scripts/az/01_post_deploy_rbac.ps1 -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup
./scripts/az/02_seed_app_settings.ps1 -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -AoaiDeploymentSegment $AoaiDeploymentSegment -AoaiDeploymentClassify $AoaiDeploymentClassify -AoaiDeploymentExtract $AoaiDeploymentExtract
./scripts/az/03_create_search_index.ps1 -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup
./scripts/az/04_publish_function.ps1 -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup

Write-Host "End-to-end deployment completed."
Write-Host "If Fabric integration is required, run scripts/az/05_add_function_mi_to_fabric.ps1 with tenant/workspace/principal values."
