from __future__ import annotations

import json

from src.claim_processing_function.adapters.doc_intelligence_client import PagePayload
from src.claim_processing_function.adapters.openai_client import AzureOpenAIAdapter


def extract_fields(
    segment_text: str,
    document_type: str,
    pages: list[PagePayload],
    schema: dict,
    prompt: str,
    client: AzureOpenAIAdapter,
    function_definition: dict,
) -> dict:
    content = (
        f"document_type={document_type}\n"
        f"schema={json.dumps(schema, ensure_ascii=True)}\n"
        f"segment={segment_text}"
    )
    payload = client.extract(
        content,
        prompt,
        image_base64=pages[0].image_base64 if pages else None,
        image_mime_type=pages[0].image_mime_type if pages else None,
        function_definition=function_definition,
    )
    return {
        "fields": payload.get("fields", {}),
        "summary": payload.get("summary", ""),
    }


def summarize_photo(
    segment_text: str,
    page: PagePayload,
    prompt: str,
    client: AzureOpenAIAdapter,
) -> str:
    payload = client.extract(
        text=f"Describe this visual evidence in two sentences.\ncontext={segment_text}",
        prompt=prompt,
        image_base64=page.image_base64,
        image_mime_type=page.image_mime_type,
    )
    summary = payload.get("summary")
    if isinstance(summary, str) and summary.strip():
        return summary.strip()
    return "Visual evidence image attached. Content requires human review for exact details."
