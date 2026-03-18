# Claims Processor

Enterprise-grade claims document pipeline for folder-based intake, segmentation, extraction, classification, and persistence to Cosmos and Azure AI Search.

## Architecture
![Claims Processor Architecture](docs/architecture.png)

The diagram above shows the full flow from claim-ready event through OCR/model processing and persistence to Cosmos/Search.

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

## Core Runtime Flow (Step-by-Step)
1. **Claim ready event arrives**
   - `ClaimIntake` receives a Service Bus message from `%SERVICEBUS_READY_QUEUE_NAME%`.
   - Payload is validated against `ReadyEvent` and `claim_id` is resolved from either:
     - explicit `claim_id`, or
     - `blob_path` folder convention (including `_ready.json` marker path).
2. **Intake enqueues processing job**
   - `ClaimIntake` sends this message to `%SERVICEBUS_PROCESSING_QUEUE_NAME%` with `session_id=claim_id`:
     - `claim_id`
     - `correlation_id`
     - `trigger`
3. **Processor enumerates claim files**
   - `ClaimProcessing` lists blob files under `<claim_id>/` (plus optional prefix) and only keeps:
     - `.pdf`, `.jpg`, `.jpeg`, `.tiff`, `.tif`, `.png`
   - `_READY.json` marker files are ignored.
4. **Idempotency gate per blob version**
   - Before processing each file, pipeline checks Cosmos ledger key:
     - `claim_id | blob_path | etag | pipeline_version`
   - If found, that file is skipped.
5. **OCR/page extraction**
   - Document Intelligence `prebuilt-read` extracts page text.
   - Output is normalized to `PagePayload[]` with:
     - `page_index`
     - `text`
     - optional `image_base64` + `image_mime_type` (for image files, first page)
     - `source_name`
6. **Segmentation model call (function calling)**
   - Pipeline sends compact OCR pages plus optional first-page image to segmentation model.
   - Expected function-call result:
     - `documents: [{ doc_name, page_index[] }]`
   - Pipeline then programmatically slices pages by returned `page_index[]`.
7. **Per-segment extraction + classification**
   - For each segment (joined page text):
     - Extraction returns `fields` + optional `summary`
     - Classification returns:
       - `document_type`
       - `database` (`cosmos` or `index`)
       - optional `reason`
   - If classifier returns invalid `database`, fallback rule applies:
     - long text -> `index`
     - short text -> `cosmos`
   - Photo-like short segments are forced to `cosmos` and summarized with vision prompt.
8. **Persistence**
   - Every segment is upserted to Cosmos records container with canonical metadata.
   - For `database=index`, segment text is chunked without splitting pages, then uploaded to Search.
   - If embeddings are enabled, each search chunk also gets `content_vector`.
   - Ledger is upserted with processing status and counts.
9. **Update endpoint**
   - `ApplyClaimUpdate` (`POST /api/apply-claim-update`) supports direct record update paths.

## Runtime Payloads and Stored Fields
### Intake -> Processing queue payload
- `claim_id`
- `correlation_id`
- `trigger`

### Cosmos record fields (per segmented document)
- `id`
- `claim_id`
- `blob_path`
- `etag`
- `document_type`
- `database_target`
- `content`
- `extracted_fields`
- `document_summary`
- `status`
- `created_at`
- `updated_at`
- `pipeline_version`

### Cosmos ledger fields (per processed source blob version)
- `id` = `claim_id|blob_path|etag|pipeline_version`
- `claim_id`
- `blob_path`
- `etag`
- `pipeline_version`
- `status`
- `processed_at`
- `metadata.doc_count`
- `metadata.indexed_chunk_count`

### Azure AI Search document fields (when routed to `index`)
- `id`
- `claim_id`
- `document_id`
- `chunk_id`
- `document_name`
- `content`
- `document_summary`
- `created_at`
- optional `content_vector` (when embeddings enabled)

## Function-Calling Contracts
These JSON contracts are supplied as tool/function definitions in model calls:
- `src/function_definitions/segmentation/segment_docs_v1.json`
- `src/function_definitions/extraction/extract_fields_v1.json`
- `src/function_definitions/classification/classify_doc_v1.json`

### Segmentation contract
- Function name: `segment_documents`
- Required top-level field: `documents`
- Required per document:
  - `doc_name: string`
  - `page_index: integer[]`

### Extraction contract
- Function name: `extract_document_fields`
- Required field:
  - `fields: object`
- Optional field:
  - `summary: string`

### Classification contract
- Function name: `classify_document`
- Required fields:
  - `document_type: string`
  - `database: "cosmos" | "index"`
- Optional field:
  - `reason: string`

You can evolve schemas/prompts/contracts without changing orchestration code, as long as required runtime fields remain compatible.

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
- `deploy`: CLI-first idempotent deployment scripts and config
- `docs`: design and operations documentation

## Path Reference
- **Function entry points**
  - `src/function_app.py`: trigger bindings and HTTP endpoints
  - `src/claim_intake_function/handler.py`: claim-ready intake -> processing queue
  - `src/claim_processing_function/handler.py`: end-to-end document processing orchestration
  - `src/claim_update_function/handler.py`: direct update workflow
- **Processing pipeline**
  - `src/claim_processing_function/pipeline/segment.py`: segmentation step
  - `src/claim_processing_function/pipeline/extract.py`: extraction step
  - `src/claim_processing_function/pipeline/classify.py`: classification + routing decision
  - `src/claim_processing_function/pipeline/persist.py`: Cosmos upsert + Search indexing
- **Adapters**
  - `src/claim_processing_function/adapters/blob_storage_client.py`: blob listing/download
  - `src/claim_processing_function/adapters/doc_intelligence_client.py`: OCR/page extraction
  - `src/claim_processing_function/adapters/openai_client.py`: chat + embeddings
  - `src/claim_processing_function/adapters/cosmos_client.py`: ledger and records persistence
  - `src/claim_processing_function/adapters/search_client.py`: Azure AI Search uploads
  - `src/processing_function/adapters/fabric_write_queue_client.py`: Service Bus queue sender
- **Config and contracts**
  - `src/common/config/settings.py`: runtime settings resolver
  - `src/model_profiles/default.yaml`: model deployment mapping
  - `src/function_definitions/**`: editable tool/function contracts for model calls
  - `src/schemas/**`: extraction/classification schema contracts
  - `src/prompts/**`: prompt files used by each stage
- **Deployment**
  - `deploy/deploy.config.toml`: single source of deployment/runtime naming and toggles
  - `deploy/deploy-infra.ps1`: idempotent infra + RBAC + app settings
  - `deploy/deploy-function.ps1`: publish function + seed assets + upsert search index
  - `deploy/README.md`: deployment walkthrough
  - `docs/DEPLOYMENT_STEPS.md`: quick command-oriented deployment sequence

## Blob Seeding Paths
`deploy/deploy-function.ps1` uploads local assets into blob containers so runtime contracts can be managed centrally.

- **Prompts container** (`storage.prompts_container_name`)
  - `src/prompts/segmentation/segment_v1.txt` -> `seed.segmentation_prompt_blob_name`
  - `src/prompts/classification/classify_v1.txt` -> `seed.classification_prompt_blob_name`
  - `src/prompts/extraction/extract_v1.txt` -> `seed.extraction_prompt_blob_name`
  - `src/prompts/extraction/photo_summary_v1.txt` -> `seed.photo_summary_prompt_blob_name`
- **Function-definitions container** (`storage.function_definitions_container_name`)
  - `src/function_definitions/segmentation/segment_docs_v1.json` -> `seed.segmentation_fn_blob_name`
  - `src/function_definitions/extraction/extract_fields_v1.json` -> `seed.extraction_fn_blob_name`
  - `src/function_definitions/classification/classify_doc_v1.json` -> `seed.classification_fn_blob_name`
- **Schemas container** (`storage.schemas_container_name`)
  - `src/schemas/extraction/claim_core_v1.json` -> `seed.extraction_schema_blob_name`
  - `src/schemas/classification/doc_types_v1.json` -> `seed.classification_schema_blob_name`

## Quick Start (Local)
1. `python -m venv .venv`
2. `.venv\\Scripts\\Activate.ps1`
3. `pip install -e .[dev]`
4. Copy `local.settings.json.example` to `local.settings.json`
5. Set required values
6. `func start`

## Infrastructure and Deployment Scripts
- `deploy/deploy.config.toml`: central config for names, queues, Cosmos/Search/OpenAI, and seeding paths
- `deploy/deploy-infra.ps1`: idempotent Azure CLI infrastructure provisioning and app settings
- `deploy/deploy-function.ps1`: function publish, blob seeding, and idempotent AI Search index upsert
- `deploy/README.md`: step-by-step deployment workflow

## Deployment Notes
- All services are deployed idempotently, including Cosmos account/database/containers and AI Search service/index.
- If `search.deploy_search_service=false`, the script reuses an existing AI Search service name from config and still idempotently ensures the index.
- OpenAI model deployments (single `gpt-5-mini` chat deployment + `text-embedding-3-large` embedding) are created only if missing.
- Prompt/function-definition/schema assets are seeded during `deploy-function.ps1` (not infra), matching your push-time seeding pattern.
