from __future__ import annotations

import json
import logging

from src.claim_processing_function.adapters.blob_storage_client import BlobStorageAdapter
from src.claim_processing_function.adapters.cosmos_client import CosmosAdapter
from src.claim_processing_function.adapters.doc_intelligence_client import DocumentIntelligenceAdapter, PagePayload
from src.claim_processing_function.adapters.openai_client import AzureOpenAIAdapter
from src.claim_processing_function.pipeline.classify import classify_document
from src.claim_processing_function.pipeline.extract import extract_fields, summarize_photo
from src.claim_processing_function.pipeline.persist import persist_outputs
from src.claim_processing_function.pipeline.segment import segment_document
from src.common.config.settings import get_settings
from src.common.logging.telemetry import log_event


def _slice_pages(pages: list[PagePayload], indexes: list[int]) -> list[PagePayload]:
    lookup = {p.page_index: p for p in pages}
    selected = [lookup[i] for i in indexes if i in lookup]
    return selected if selected else pages


def process_claim(message_body: bytes, logger: logging.Logger) -> None:
    settings = get_settings()
    payload = json.loads(message_body.decode('utf-8'))
    claim_id = payload['claim_id']
    correlation_id = payload.get('correlation_id', claim_id)

    blob_client = BlobStorageAdapter(
        account_url=settings.blob_account_url,
        container_name=settings.blob_container,
    )
    cosmos_client = CosmosAdapter(
        endpoint=settings.cosmos_endpoint,
        database_name=settings.cosmos_database,
        ledger_container=settings.cosmos_ledger_container,
        records_container=settings.cosmos_records_container,
    )
    doc_client = DocumentIntelligenceAdapter(settings.docintel_endpoint)
    ai_client = AzureOpenAIAdapter(settings)

    docs = blob_client.list_claim_documents(claim_id=claim_id, prefix=settings.blob_claims_prefix)
    log_event(logger, "claim_docs_discovered", correlation_id, claim_id=claim_id, doc_count=len(docs))

    processed_count = 0
    skipped_count = 0

    for doc in docs:
        if cosmos_client.is_already_processed(
            claim_id=claim_id,
            blob_path=doc.blob_path,
            etag=doc.etag,
            pipeline_version=settings.pipeline_version,
        ):
            skipped_count += 1
            continue

        try:
            raw = blob_client.download_bytes(doc.blob_path)
            pages = doc_client.extract_pages(raw, doc.content_type, doc.blob_path.split("/")[-1])

            doc_groups = segment_document(
                pages,
                settings.segment_prompt,
                ai_client,
                settings.segmentation_fn,
            )

            processed_docs: list[dict] = []
            for group in doc_groups:
                group_pages = _slice_pages(pages, group["page_index"])
                page_texts = [p.text for p in group_pages if p.text]
                combined_text = "\n\n".join(page_texts)
                first_page = group_pages[0] if group_pages else None

                extraction = extract_fields(
                    combined_text,
                    "unknown",
                    group_pages,
                    settings.extraction_schema,
                    settings.extract_prompt,
                    ai_client,
                    settings.extraction_fn,
                )

                classification = classify_document(
                    combined_text,
                    group_pages,
                    settings.classification_schema,
                    settings.classify_prompt,
                    ai_client,
                    settings.classification_fn,
                )
                if classification["database"] not in {"cosmos", "index"}:
                    classification["database"] = "index" if len(combined_text) > 5000 else "cosmos"

                # Photo-style outputs always stay in Cosmos with short summary.
                if first_page and first_page.image_base64 and (len(combined_text.strip()) < 120):
                    classification["database"] = "cosmos"
                    extraction["summary"] = summarize_photo(
                        combined_text,
                        first_page,
                        settings.photo_summary_prompt,
                        ai_client,
                    )

                processed_docs.append(
                    {
                        "doc_name": group["doc_name"],
                        "document_type": classification["document_type"],
                        "database": classification["database"],
                        "classification_reason": classification.get("reason", ""),
                        "fields": extraction.get("fields", {}),
                        "summary": extraction.get("summary", ""),
                        "full_text": combined_text,
                        "page_texts": page_texts,
                    }
                )

            persist_outputs(
                claim_id=claim_id,
                blob_path=doc.blob_path,
                etag=doc.etag,
                processed_docs=processed_docs,
                settings=settings,
                status="processed",
            )
            processed_count += 1
        except Exception as exc:
            cosmos_client.upsert_ledger(
                claim_id=claim_id,
                blob_path=doc.blob_path,
                etag=doc.etag,
                pipeline_version=settings.pipeline_version,
                status="failed",
                metadata={"error": str(exc)},
            )
            log_event(
                logger,
                "claim_doc_failed",
                correlation_id,
                claim_id=claim_id,
                blob_path=doc.blob_path,
                error=str(exc),
            )

    log_event(
        logger,
        "claim_processing_complete",
        correlation_id,
        claim_id=claim_id,
        processed_count=processed_count,
        skipped_count=skipped_count,
    )
