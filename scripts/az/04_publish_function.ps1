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
$functionAppName = $o.functionAppName.value

if (Get-Command func -ErrorAction SilentlyContinue) {
  Write-Host "Publishing via Functions Core Tools"
  func azure functionapp publish $functionAppName --python
} else {
  Write-Host "Functions Core Tools not found. Falling back to zip deploy."
  $zipPath = ".deploy/functionapp.zip"
  New-Item -ItemType Directory -Path .deploy -Force | Out-Null
  if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
  Compress-Archive -Path * -DestinationPath $zipPath -Force
  az functionapp deployment source config-zip --resource-group $ResourceGroup --name $functionAppName --src $zipPath | Out-Null
}

Write-Host "Function app publish completed for $functionAppName"
