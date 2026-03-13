# Claims Processor

Enterprise-grade repository scaffold for the Azure-based claims document intelligence solution.

## Core Flow
- `_READY.json` event indicates claim folder reconciliation window.
- Logic App or Event Grid routes processable claim events to Service Bus.
- `ClaimIntake` function enqueues claim processing work.
- `ClaimProcessing` function loads new/changed files, segments, classifies, extracts, and writes:
  - Canonical metadata and ledger to Cosmos DB
  - Retrieval payloads and chunks to Azure AI Search
- `ClaimUpdate` function supports direct update workflows.

## Implemented Modules
- Blob reconciliation adapter with per-claim listing and `_READY.json` ignore logic.
- Cosmos adapter with processing ledger idempotency and records persistence.
- AI Search adapter for chunk upload.
- Segmentation, classification, and extraction pipeline stages with schema and prompt control.
- Claim update path for patching persisted records.

## Project Layout
- `src/claim_intake_function`: intake trigger and queue orchestration
- `src/claim_processing_function`: segmentation, classification, extraction pipeline
- `src/claim_update_function`: update and reprocessing operations
- `src/schemas`: config-driven extraction and classification schemas
- `src/model_profiles`: model deployment config
- `infra/bicep`: infra and RBAC templates
- `docs`: technical design and operations runbook

## Quick Start
1. `python -m venv .venv`
2. `.venv\\Scripts\\Activate.ps1`
3. `pip install -e .[dev]`
4. Copy `local.settings.json.example` to `local.settings.json`
5. Set environment values
6. `func start`

## Notes
- Auth path uses `DefaultAzureCredential`.
- Schema and prompt changes do not require code changes when contracts are stable.
