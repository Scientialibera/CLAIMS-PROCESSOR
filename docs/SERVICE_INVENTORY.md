# BERKLEY_CLAIMS — End-to-End Service Inventory

Complete inventory of every service, resource, identity, and connection required to run the Claims Document Intelligence pipeline.

---

## 1. Naming Convention Table

### Azure Resources

| # | Service Type | Dev Name | Prod Name | Notes |
|---|---|---|---|---|
| 1 | **Resource Group** | `rg-berkleyclaims` | `rg-berkleyclaims-prod` | Container for all Azure resources |
| 2 | **Azure Function App** | `func-berkleyclaims` | `func-berkleyclaims-prod` | Python 3.11, Flex Consumption, Functions v4 |
| 3 | **Storage Account** | `stberkleyclaims` | `stberkleyclaimsprod` | Function runtime + claims/prompts/schemas blobs |
| 4 | **Service Bus Namespace** | `sbns-berkleyclaims` | `sbns-berkleyclaims-prod` | Standard tier; hosts both queues |
| 5 | **Service Bus Queue — Ready** | `q-claim-ready` | `q-claim-ready` | Standard queue (no sessions) — intake trigger |
| 6 | **Service Bus Queue — Process** | `q-claim-process` | `q-claim-process` | Session-enabled (`session_id = claim_id`) |
| 7 | **Azure OpenAI** | `aoai-berkleyclaims` | `aoai-berkleyclaims-prod` | Standalone `OpenAI` kind; hosts all model deployments |
| 8 | **Document Intelligence** | `doci-berkleyclaims` | `doci-berkleyclaims-prod` | `AIServices` kind with custom subdomain; `prebuilt-read` model |
| 9 | **Cosmos DB** | `cosmos-berkleyclaims` | `cosmos-berkleyclaims-prod` | SQL API; `claims` database |
| 10 | **AI Search** | `srch-berkleyclaims` | `srch-berkleyclaims-prod` | Basic SKU; `claims-index` |
| 11 | **Application Insights** | `appi-berkleyclaims` | `appi-berkleyclaims-prod` | Telemetry, traces by `claim_id` |
| 12 | **Log Analytics Workspace** | `law-berkleyclaims` | `law-berkleyclaims-prod` | Backend for App Insights |

---

## 2. Managed Identity & RBAC

| Principal | Target Resource | Role | Purpose |
|---|---|---|---|
| Function App MI | `q-claim-ready` | Azure Service Bus Data Receiver | Trigger on intake messages |
| Function App MI | `q-claim-process` | Azure Service Bus Data Sender | Enqueue processing jobs |
| Function App MI | `q-claim-process` | Azure Service Bus Data Receiver | Trigger on processing messages |
| Function App MI | Storage Account | Storage Blob Data Contributor | Read claims, write results |
| Function App MI | Azure OpenAI | Cognitive Services User | LLM calls (segment, classify, extract, embed) |
| Function App MI | Document Intelligence | Cognitive Services User | OCR/text extraction |
| Function App MI | AI Search | Search Index Data Contributor | Index writes and queries |
| Function App MI | Cosmos DB | Cosmos DB Built-in Data Contributor | Read/write ledger and records |

---

## 3. Azure OpenAI Model Deployments

| Deployment Name | Model | Purpose |
|---|---|---|
| `gpt-5-mini` | gpt-5-mini | Single chat deployment for all roles (segment, classify, extract) |
| `text-embedding-3-large` | text-embedding-3-large | Embedding for AI Search |

---

## 4. Blob Storage Containers

| Container | Purpose |
|---|---|
| `claims` | Source claim document packages (PDFs, images) |
| `prompts` | Versioned LLM prompts (segment, classify, extract, photo summary) |
| `function-definitions` | OpenAI function-calling JSON definitions |
| `schemas` | Extraction and classification schemas |

---

## 5. Cosmos DB Collections

| Database | Container | Partition Key | Purpose |
|---|---|---|---|
| `claims` | `processing_ledger` | `/claim_id` | Tracks processing state per claim |
| `claims` | `processed_records` | `/claim_id` | Final extracted and classified records |

---

## 6. Critical Integration Notes

| # | Requirement | Detail |
|---|---|---|
| 1 | **Extension Bundle** | `host.json` must include `extensionBundle` with `Microsoft.Azure.Functions.ExtensionBundle` v4. Without it, Service Bus triggers silently fail to register. |
| 2 | **Doc Intelligence Custom Subdomain** | Token auth (Managed Identity) requires a custom subdomain endpoint (`https://<name>.cognitiveservices.azure.com/`). Regional endpoints return `BadRequest`. Deploy script now ensures custom subdomain exists. |
| 3 | **Doc Intelligence SDK** | Uses `azure-ai-documentintelligence`. Import: `DocumentIntelligenceClient`, `AnalyzeDocumentRequest(bytes_source=...)`. |
| 4 | **Doc Intelligence Kind** | Deployed as `AIServices` kind (multi-service Cognitive Services). Shares endpoint for future cognitive services. |
| 5 | **Azure OpenAI Kind** | Deployed as standalone `OpenAI` kind. Easier to manage, clearer cost attribution. Custom subdomain required for token auth. |
| 6 | **AOAI Auth** | Use `get_bearer_token_provider(credential, "https://cognitiveservices.azure.com/.default")` with the `openai` Python SDK, or raw `Bearer` token via REST. |
| 7 | **PyMuPDF** | PDF pages can be rendered to PNG via `fitz` for multimodal LLM input. Dependency: `PyMuPDF>=1.24.0`. |
| 8 | **Session Queues** | Processing queue is session-enabled (`session_id = claim_id`). `host.json` must configure `sessionHandlerOptions`. |

---

## 7. Configuration Files

| File / Blob | Purpose |
|---|---|
| `prompts/segmentation/segment_v1.txt` | LLM prompt for document segmentation |
| `prompts/classification/classify_v1.txt` | LLM prompt for document classification |
| `prompts/extraction/extract_v1.txt` | LLM prompt for field extraction |
| `prompts/extraction/photo_summary_v1.txt` | LLM prompt for photo evidence summary |
| `src/schemas/extraction/claim_core_v1.json` | JSON schema defining claim fields |
| `src/schemas/classification/doc_types_v1.json` | Document type classification schema |
| `src/function_definitions/segmentation/segment_docs_v1.json` | OpenAI function def for segmentation |
| `src/function_definitions/classification/classify_doc_v1.json` | OpenAI function def for classification |
| `src/function_definitions/extraction/extract_fields_v1.json` | OpenAI function def for extraction |
| `src/model_profiles/default.yaml` | Model deployment names, temperature, max tokens |

---

## 8. Network / Connectivity Summary

```
Blob Trigger (claim package) ──► Service Bus (q-claim-ready)
                                      │
                                      ▼
                              Azure Function (ClaimIntake)
                               └─► Service Bus (q-claim-process, send)
                                      │
                                      ▼
                              Azure Function (ClaimProcessing)
                               ├─► Document Intelligence (REST)
                               ├─► Azure OpenAI (REST) — segment, classify, extract, embed
                               ├─► Storage Account (blob read)
                               ├─► Cosmos DB (ledger + records)
                               └─► AI Search (index upsert)
```

All connections use **Managed Identity + `DefaultAzureCredential`**.

---

## 9. Total Resource Count

| Category | Count |
|---|---|
| Azure Resources (RG, Function, Storage, SB, AOAI, DI, Cosmos, Search, AppInsights, LAW) | 12 |
| Managed Identities | 1 (Function App) |
| RBAC Assignments | 8 |
| Cosmos Data-Plane Assignments | 1 |
| **Total distinct resources/configurations** | **~22** |
