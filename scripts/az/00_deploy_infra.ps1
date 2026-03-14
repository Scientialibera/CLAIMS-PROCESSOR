param(
  [Parameter(Mandatory=$true)][string]$SubscriptionId,
  [Parameter(Mandatory=$true)][string]$ResourceGroup,
  [Parameter(Mandatory=$true)][ValidateSet('dev','prod')][string]$Environment,
  [string]$Location = 'eastus2'
)

$ErrorActionPreference = 'Stop'

Write-Host "Setting subscription: $SubscriptionId"
az account set --subscription $SubscriptionId | Out-Null

if (-not (az group exists --name $ResourceGroup | ConvertFrom-Json)) {
  Write-Host "Creating resource group: $ResourceGroup in $Location"
  az group create --name $ResourceGroup --location $Location | Out-Null
}

$paramFile = "infra/bicep/parameters/$Environment.bicepparam"
if (-not (Test-Path $paramFile)) {
  throw "Parameter file not found: $paramFile"
}

Write-Host "Deploying bicep with parameter file: $paramFile"
$deploy = az deployment group create `
  --resource-group $ResourceGroup `
  --template-file infra/bicep/main.bicep `
  --parameters $paramFile `
  --query "properties.outputs" -o json

if (-not $deploy) {
  throw "Deployment returned empty outputs"
}

New-Item -ItemType Directory -Path .deploy -Force | Out-Null
$deploy | Set-Content -Encoding UTF8 .deploy/outputs.json
Write-Host "Deployment outputs saved to .deploy/outputs.json"
