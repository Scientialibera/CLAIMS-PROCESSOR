# Deployment Steps

## Prerequisites
- Azure CLI logged in: `az login`
- Functions Core Tools installed (`func`)
- Python 3.11+ available on path

## Configure Once
Update `deploy/deploy.config.toml`:
- `azure.subscription_id`
- `azure.location`
- Optional explicit names under `naming`
- Toggle reuse/create behavior:
  - `search.deploy_search_service`
  - `openai.deploy_openai_resources`
  - `docintel.deploy_docintel_resources`

## Step-by-Step
1. Deploy infrastructure (idempotent)
```powershell
pwsh ./deploy/deploy-infra.ps1
```

2. Publish function + seed assets + upsert index (idempotent)
```powershell
pwsh ./deploy/deploy-function.ps1
```

## What Is Idempotent
- Resource group
- Storage account + containers
- Service Bus namespace + queues
- Cosmos account + SQL database + containers
- Search service (optional create/reuse) + search index upsert
- OpenAI (standalone `OpenAI` kind) and Doc Intelligence (`AIServices` kind) accounts (create/reuse)
- Custom subdomain on OpenAI and Doc Intelligence accounts (required for token auth)
- OpenAI model deployments: single `gpt-5-mini` chat deployment + `text-embedding-3-large` embedding (create-if-missing)
- RBAC role assignments and Cosmos SQL data-plane role assignment

## Critical Post-Deploy Checks
1. Verify `DOCINTEL_ENDPOINT` uses the custom subdomain form (`https://<name>.cognitiveservices.azure.com/`), not the regional endpoint
2. Verify `extensionBundle` is present in `host.json` — without it, Service Bus triggers silently fail
3. Verify Function App MI has `Cognitive Services User` role on both OpenAI and Doc Intelligence accounts
