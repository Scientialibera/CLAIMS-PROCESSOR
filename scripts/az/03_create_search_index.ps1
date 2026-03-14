param(
  [Parameter(Mandatory=$true)][string]$SubscriptionId,
  [Parameter(Mandatory=$true)][string]$ResourceGroup,
  [string]$IndexName = 'claims-index'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path .deploy/outputs.json)) {
  throw "Missing .deploy/outputs.json. Run 00_deploy_infra.ps1 first."
}

az account set --subscription $SubscriptionId | Out-Null
$o = Get-Content .deploy/outputs.json | ConvertFrom-Json
$searchServiceName = $o.searchServiceName.value

$adminKey = az search admin-key show --resource-group $ResourceGroup --service-name $searchServiceName --query primaryKey -o tsv
if (-not $adminKey) {
  throw "Could not get search admin key."
}
$endpoint = "https://$searchServiceName.search.windows.net"

$schema = @{
  name = $IndexName
  fields = @(
    @{ name='id'; type='Edm.String'; key=$true; searchable=$false; filterable=$true; sortable=$false; facetable=$false; retrievable=$true },
    @{ name='claim_id'; type='Edm.String'; searchable=$false; filterable=$true; sortable=$true; facetable=$true; retrievable=$true },
    @{ name='document_id'; type='Edm.String'; searchable=$false; filterable=$true; sortable=$false; facetable=$false; retrievable=$true },
    @{ name='chunk_id'; type='Edm.String'; searchable=$false; filterable=$true; sortable=$false; facetable=$false; retrievable=$true },
    @{ name='document_name'; type='Edm.String'; searchable=$true; filterable=$true; sortable=$true; facetable=$false; retrievable=$true },
    @{ name='content'; type='Edm.String'; searchable=$true; filterable=$false; sortable=$false; facetable=$false; retrievable=$true },
    @{ name='document_summary'; type='Edm.String'; searchable=$true; filterable=$false; sortable=$false; facetable=$false; retrievable=$true },
    @{ name='created_at'; type='Edm.String'; searchable=$false; filterable=$true; sortable=$true; facetable=$false; retrievable=$true }
  )
} | ConvertTo-Json -Depth 10

$headers = @{ 'Content-Type'='application/json'; 'api-key'=$adminKey }
$uri = "$endpoint/indexes/$IndexName`?api-version=2023-11-01"
Invoke-RestMethod -Method Put -Uri $uri -Headers $headers -Body $schema | Out-Null
Write-Host "Search index ensured: $IndexName"
