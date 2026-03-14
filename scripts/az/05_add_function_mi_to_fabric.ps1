param(
  [Parameter(Mandatory=$true)][string]$TenantId,
  [Parameter(Mandatory=$true)][string]$FabricWorkspaceId,
  [Parameter(Mandatory=$true)][string]$PrincipalObjectId,
  [string]$WorkspaceRole = 'Contributor'
)

$ErrorActionPreference = 'Stop'

$token = az account get-access-token --resource https://api.fabric.microsoft.com --tenant $TenantId --query accessToken -o tsv
if (-not $token) {
  throw "Unable to acquire Fabric API token"
}

$headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }
$body = @{
  principal = @{
    id = $PrincipalObjectId
    type = 'ServicePrincipal'
  }
  role = $WorkspaceRole
} | ConvertTo-Json -Depth 8

$uri = "https://api.fabric.microsoft.com/v1/workspaces/$FabricWorkspaceId/roleAssignments"
Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body | Out-Null
Write-Host "Assigned Fabric workspace role '$WorkspaceRole' to principal '$PrincipalObjectId'"
