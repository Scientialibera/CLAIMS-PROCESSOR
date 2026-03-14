# Claims Processor

Enterprise-grade claims document pipeline for folder-based intake, segmentation, extraction, classification, and persistence to Cosmos and Azure AI Search.

## What This Implements
- `_READY.json` acts as the claim-folder start indicator.
- Only these file types are processed from the claim folder:
  - `.pdf`
  - `.jpg`
  - `.jpeg`
  - `.tiff`
  - `.tif`
  - `.png`
- Files are converted to page-level text before model processing.
- Three model calls are executed per flow:
  1. Segmentation call returns logical docs as `[{doc_name, page_index[]}]`
  2. Extraction call returns fields for each segmented doc
  3. Classification call returns enum routing, including `database: cosmos | index`
- Classification-based routing:
  - `cosmos` for short operational docs such as receipts, medical exams, photos
  - `index` for long narrative docs such as claim reports
- Index chunking is page-safe:
  - Chunk by token target
  - Never split a page in half
- Photo segments are summarized in two short sentences and stored in Cosmos.
- Ledger idempotency is enforced through Cosmos using claim, blob path, etag, and pipeline version.

## Core Runtime Flow
1. Event source posts claim-ready message to Service Bus.
2. `ClaimIntake` validates payload and enqueues processing by `claim_id` session.
3. `ClaimProcessing` reconciles claim folder contents from Blob.
4. New or changed documents are OCR-parsed and segmented.
5. Each segmented doc is extracted and classified.
6. Outputs are persisted:
   - Canonical records and processing ledger to Cosmos DB
   - Index-target chunks to Azure AI Search
7. `ApplyClaimUpdate` supports direct update paths for records.

## Function-Definition Driven Model Calls
All three model contracts are editable JSON files:
- `src/function_definitions/segmentation/segment_docs_v1.json`
- `src/function_definitions/extraction/extract_fields_v1.json`
- `src/function_definitions/classification/classify_doc_v1.json`

You can add, remove, or rename fields without changing core pipeline code, as long as downstream contracts are respected.

## Config-Driven Extensibility
- Extraction schema:
  - `src/schemas/extraction/claim_core_v1.json`
- Classification schema:
  - `src/schemas/classification/doc_types_v1.json`
- Prompts:
  - `src/prompts/segmentation/segment_v1.txt`
  - `src/prompts/extraction/extract_v1.txt`
  - `src/prompts/extraction/photo_summary_v1.txt`
  - `src/prompts/classification/classify_v1.txt`
- Model profile:
  - `src/model_profiles/default.yaml`

Switch active versions with env vars in `local.settings.json`.

## Authentication
- Uses `DefaultAzureCredential` across all adapters.
- Designed for managed identity in Azure-hosted runtime.

## Project Layout
- `src/claim_intake_function`: intake trigger and queue orchestration
- `src/claim_processing_function`: blob reconciliation, OCR, segmentation, extraction, classification, persistence
- `src/claim_update_function`: direct update workflow
- `src/common`: auth, config, models, logging, utility helpers
- `src/function_definitions`: editable model function contracts
- `src/schemas`: editable business schemas
- `infra/bicep`: full infrastructure templates
- `scripts/az`: deployment and post-deploy scripts
- `docs`: design and operations documentation

## Quick Start (Local)
1. `python -m venv .venv`
2. `.venv\\Scripts\\Activate.ps1`
3. `pip install -e .[dev]`
4. Copy `local.settings.json.example` to `local.settings.json`
5. Set required values
6. `func start`

## Infrastructure and Deployment Scripts
- `infra/bicep/main.bicep`: orchestrates full stack deployment
- `infra/bicep/modules/*`: storage, service bus, cosmos, search, cognitive, key vault, observability, function app
- `scripts/az/00_deploy_infra.ps1`: deploy infra and write `.deploy/outputs.json`
- `scripts/az/01_post_deploy_rbac.ps1`: apply managed identity RBAC and Cosmos data role
- `scripts/az/02_seed_app_settings.ps1`: seed function app settings from deployment outputs
- `scripts/az/03_create_search_index.ps1`: create search index schema
- `scripts/az/04_publish_function.ps1`: publish function code
- `scripts/az/05_add_function_mi_to_fabric.ps1`: optional Fabric role assignment via API
- `scripts/az/99_full_deploy.ps1`: end-to-end deploy entrypoint
