# Deployment Steps

## Prerequisites
- Azure CLI logged in: `az login`
- Functions Core Tools installed for direct publish (`func`) or use zip-deploy fallback
- Contributor access on subscription/resource group
- If using Fabric integration, tenant/workspace admin approval

## Option A: End-to-End Script
Run from repo root:

```powershell
./scripts/az/99_full_deploy.ps1 `
  -SubscriptionId <sub-id> `
  -ResourceGroup <rg-name> `
  -Environment dev `
  -Location eastus2
```

## Option B: Step-by-Step
1. Deploy infrastructure
```powershell
./scripts/az/00_deploy_infra.ps1 -SubscriptionId <sub-id> -ResourceGroup <rg-name> -Environment dev -Location eastus2
```
2. Assign RBAC for managed identity and data-plane access
```powershell
./scripts/az/01_post_deploy_rbac.ps1 -SubscriptionId <sub-id> -ResourceGroup <rg-name>
```
3. Seed Function app settings
```powershell
./scripts/az/02_seed_app_settings.ps1 -SubscriptionId <sub-id> -ResourceGroup <rg-name>
```
4. Create Azure AI Search index
```powershell
./scripts/az/03_create_search_index.ps1 -SubscriptionId <sub-id> -ResourceGroup <rg-name>
```
5. Publish Function app
```powershell
./scripts/az/04_publish_function.ps1 -SubscriptionId <sub-id> -ResourceGroup <rg-name>
```

## Fabric Role Assignment (Optional)
Fabric workspace assignment is not available through ARM/Bicep. Use:

```powershell
./scripts/az/05_add_function_mi_to_fabric.ps1 `
  -TenantId <tenant-id> `
  -FabricWorkspaceId <workspace-id> `
  -PrincipalObjectId <function-mi-object-id> `
  -WorkspaceRole Contributor
```
