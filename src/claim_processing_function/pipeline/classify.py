from __future__ import annotations

import json

from src.claim_processing_function.adapters.doc_intelligence_client import PagePayload
from src.claim_processing_function.adapters.openai_client import AzureOpenAIAdapter


def classify_document(
    segment_text: str,
    pages: list[PagePayload],
    schema: dict,
    prompt: str,
    client: AzureOpenAIAdapter,
    function_definition: dict,
) -> dict:
    payload = client.classify(
        f"schema={json.dumps(schema, ensure_ascii=True)}\nsegment={segment_text}",
        prompt,
        image_base64=pages[0].image_base64 if pages else None,
        image_mime_type=pages[0].image_mime_type if pages else None,
        function_definition=function_definition,
    )
    return {
        "document_type": payload.get("document_type", "unknown"),
        "database": payload.get("database", "index"),
        "reason": payload.get("reason", ""),
    }
