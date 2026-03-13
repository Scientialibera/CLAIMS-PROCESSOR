from __future__ import annotations

import json
import logging

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

    doc_client = DocumentIntelligenceAdapter(settings.docintel_endpoint)
    ai_client = AzureOpenAIAdapter(settings)

    # Placeholder sample text. Replace with blob reconciliation loader.
    source_text = f'claim_id={claim_id} sample document body'
    _ = doc_client
    segments = segment_document(source_text, settings.segment_prompt, ai_client)

    processed: list[dict] = []
    for seg in segments:
        doc_type = classify_document(seg, settings.classification_schema, settings.classify_prompt, ai_client)
        fields = extract_fields(seg, doc_type, settings.extraction_schema, settings.extract_prompt, ai_client)
        processed.append({'document_type': doc_type, 'segment': seg, 'fields': fields})

    persist_outputs(claim_id, processed, settings)
    log_event(logger, 'claim_processing_complete', correlation_id, claim_id=claim_id, segment_count=len(segments))
