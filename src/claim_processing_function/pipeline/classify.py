from __future__ import annotations

import json

from src.claim_processing_function.adapters.openai_client import AzureOpenAIAdapter


def classify_document(segment_text: str, schema: dict, prompt: str, client: AzureOpenAIAdapter) -> str:
    payload = client.classify(
        f"schema={json.dumps(schema, ensure_ascii=True)}\nsegment={segment_text}",
        prompt,
    )
    return payload.get('document_type', 'unknown')
