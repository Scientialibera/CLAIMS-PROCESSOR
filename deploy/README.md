# Deployment (CLI + PowerShell)

This project uses idempotent Azure CLI scripts (no Bicep).

## Prerequisites
- Azure CLI logged in (`az login`)
- Functions Core Tools (`func`)
- Python 3.11+

## Configure
1. Copy `deploy/deploy.config.toml` and set:
   - `azure.subscription_id`
   - `azure.resource_group_name` (optional; defaults to `rg-<prefix>`)
   - naming overrides only when you need explicit existing names
2. For existing services:
   - Set `naming.search_service_name` and `search.deploy_search_service=false` to reuse existing search service.
   - Set `openai.deploy_openai_resources=false` and/or `docintel.deploy_docintel_resources=false` to reuse existing cognitive accounts in the target resource group.

## Deploy Infrastructure
```powershell
pwsh ./deploy/deploy-infra.ps1
```

What this does (idempotent):
- Resource group, storage account, containers, Service Bus namespace/queues
- Cosmos DB account/database/containers
- AI Search service (optional create/reuse)
- Function App on Flex Consumption + system-assigned managed identity
- OpenAI + Document Intelligence account create/reuse
- OpenAI deployments: segment/classify/extract/embedding (create-if-missing)
- RBAC and Cosmos SQL data-plane role assignments
- Function app settings for runtime

## Publish Function + Seed Assets
```powershell
pwsh ./deploy/deploy-function.ps1
```

What this does (idempotent):
- Publishes function code
- Seeds prompts, function definitions, and schemas to blob containers
- Upserts the AI Search index schema (with vector field when embeddings enabled)
- Syncs function triggers
