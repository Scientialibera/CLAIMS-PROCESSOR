from __future__ import annotations

import json

from src.claim_processing_function.adapters.openai_client import AzureOpenAIAdapter


def extract_fields(segment_text: str, document_type: str, schema: dict, prompt: str, client: AzureOpenAIAdapter) -> dict:
    content = (
        f"document_type={document_type}\n"
        f"schema={json.dumps(schema, ensure_ascii=True)}\n"
        f"segment={segment_text}"
    )
    return client.extract(content, prompt)
