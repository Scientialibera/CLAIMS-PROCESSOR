from __future__ import annotations

import json
import logging

from src.claim_processing_function.adapters.blob_storage_client import BlobStorageAdapter
from src.claim_processing_function.adapters.cosmos_client import CosmosAdapter
from src.claim_processing_function.adapters.doc_intelligence_client import DocumentIntelligenceAdapter
from src.claim_processing_function.adapters.openai_client import AzureOpenAIAdapter
from src.claim_processing_function.pipeline.classify import classify_document
from src.claim_processing_function.pipeline.extract import extract_fields
from src.claim_processing_function.pipeline.persist import persist_outputs
from src.claim_processing_function.pipeline.segment import segment_document
from src.common.config.settings import get_settings
from src.common.logging.telemetry import log_event


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
            source_text = doc_client.extract_text(raw)
            segments = segment_document(source_text, settings.segment_prompt, ai_client)

            processed: list[dict] = []
            for seg in segments:
                doc_type = classify_document(
                    seg,
                    settings.classification_schema,
                    settings.classify_prompt,
                    ai_client,
                )
                fields = extract_fields(
                    seg,
                    doc_type,
                    settings.extraction_schema,
                    settings.extract_prompt,
                    ai_client,
                )
                processed.append({"document_type": doc_type, "segment": seg, "fields": fields})

            persist_outputs(
                claim_id=claim_id,
                blob_path=doc.blob_path,
                etag=doc.etag,
                processed=processed,
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
