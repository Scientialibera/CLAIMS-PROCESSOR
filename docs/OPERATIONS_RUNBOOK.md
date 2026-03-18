# Operations Runbook

## Monitoring

- Application Insights traces (filter by `claim_id` or `correlation_id`)
- Service Bus queue depth: `q-claim-ready` (intake) and `q-claim-process` (processing, session-enabled)
- Dead-letter queue counts — check daily
- Function execution failures and duration
- Cosmos DB request unit consumption

## Common Failures

- `AuthError`: Managed identity missing required RBAC role.
- `SchemaMismatch`: Model output does not match configured extraction or classification schema.
- `DependencyTimeout`: Retry exhausted for AOAI, Doc Intelligence, Cosmos, or Search.
- `ValidationError`: Invalid queue message payload.

## DLQ Procedure

1. Inspect dead-letter reason and correlation id.
2. Fix root cause (RBAC/config/schema mismatch).
3. Replay message from DLQ to main queue using approved ops tool.
4. Verify record status in Cosmos.

## Infrastructure Requirements

### Extension Bundle (host.json)
The `extensionBundle` section in `host.json` is **mandatory**. Without it, Service Bus trigger bindings fail to register and the Function App silently ignores queue messages.

### Document Intelligence — Custom Subdomain
Token-based authentication (Managed Identity) requires a **custom subdomain** on the Cognitive Services account. The regional endpoint (e.g. `https://eastus2.api.cognitive.microsoft.com/`) does **not** support token auth. The deploy script enforces this automatically; ensure the `DOCINTEL_ENDPOINT` uses the form `https://<account-name>.cognitiveservices.azure.com/`.

### Document Intelligence — SDK
Uses `azure-ai-documentintelligence` (not the legacy `azure-ai-formrecognizer`). The new SDK uses `DocumentIntelligenceClient` and `AnalyzeDocumentRequest(bytes_source=...)`.

### Document Intelligence — Kind
Deployed as `AIServices` kind (multi-service Cognitive Services account). Shares the custom subdomain endpoint and supports Document Intelligence alongside other cognitive services.

### Azure OpenAI — Standalone
Azure OpenAI is deployed as standalone `OpenAI` kind for easier management and clearer cost attribution. Must have a custom subdomain for token auth.

### Azure OpenAI — Authentication
Use `get_bearer_token_provider` from `azure.identity` with scope `https://cognitiveservices.azure.com/.default` for the `openai` Python SDK. Raw token via `get_access_token()` also works for REST calls.

### PyMuPDF — Multimodal Page Rendering
PDF pages can be rendered to PNG images using PyMuPDF (`fitz`) for multimodal LLM input. Both OCR text and page images can be sent to the LLM to improve extraction accuracy on complex tables.

### Service Bus Session Queues
The processing queue uses sessions (`session_id = claim_id`) to ensure ordered processing per claim. The Function App must have `sessionHandlerOptions` configured in `host.json`.

## Configuration Reference

| Setting | Default | Behavior |
|---|---|---|
| `PIPELINE_VERSION` | `v1` | Version tag applied to processing records for traceability. Allows multiple pipeline versions to coexist in Cosmos. |
| `ACTIVE_EXTRACTION_SCHEMA` | `claim_core_v1` | Selects which JSON schema under `src/schemas/extraction/` defines the expected claim fields. |
| `ACTIVE_CLASSIFICATION_SCHEMA` | `doc_types_v1` | Selects which JSON schema under `src/schemas/classification/` defines document type classes and routing targets (Cosmos vs Search). |
| `ACTIVE_SEGMENTATION_FUNCTION` | `segment_docs_v1` | Selects the OpenAI function definition under `src/function_definitions/segmentation/` used for document segmentation. |
| `ACTIVE_EXTRACTION_FUNCTION` | `extract_fields_v1` | Selects the OpenAI function definition under `src/function_definitions/extraction/` used for field extraction. |
| `ACTIVE_CLASSIFICATION_FUNCTION` | `classify_doc_v1` | Selects the OpenAI function definition under `src/function_definitions/classification/` used for document classification. |
| `ACTIVE_MODEL_PROFILE` | `default` | Selects the YAML model profile under `src/model_profiles/` mapping logical roles (segment, classify, extract) to a single AOAI deployment name (`AOAI_DEPLOYMENT`). |
| `MAX_INDEX_CHUNK_TOKENS` | `1200` | Maximum token count per chunk when splitting documents for AI Search indexing. Smaller chunks improve retrieval precision; larger chunks preserve context. |
| `SEARCH_USE_EMBEDDINGS` | `true` | When `true`, documents are embedded using the configured embedding model and stored as vectors in AI Search for semantic retrieval. When `false`, only keyword search is available. |
| `SEARCH_EMBEDDING_DIMENSIONS` | `3072` | Dimensionality of the embedding vectors. Must match the model's output dimensions (e.g. `text-embedding-3-large` outputs 3072). |

## Change Management

- Field changes: update `src/schemas/extraction/*.json`.
- Prompt changes: update `src/prompts/**/*.txt`.
- Function definition changes: update `src/function_definitions/**/*.json`.
- Model switch: update `src/model_profiles/*.yaml` and set `ACTIVE_MODEL_PROFILE`.
- Classification schema: update `src/schemas/classification/*.json`.
- Reprocess failed claims: use the `ApplyClaimUpdate` HTTP endpoint.
