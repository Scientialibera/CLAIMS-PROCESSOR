from __future__ import annotations

import json

from src.claim_processing_function.adapters.doc_intelligence_client import PagePayload
from src.claim_processing_function.adapters.openai_client import AzureOpenAIAdapter


def _compact_pages(pages: list[PagePayload]) -> str:
    payload = []
    for p in pages:
        payload.append(
            {
                "page_index": p.page_index,
                "source_name": p.source_name,
                "text": p.text,
            }
        )
    return json.dumps(payload, ensure_ascii=True)


def segment_document(
    pages: list[PagePayload],
    prompt: str,
    client: AzureOpenAIAdapter,
    function_definition: dict,
) -> list[dict]:
    if not pages:
        return []

    response = client.segment(
        text=f"pages={_compact_pages(pages)}",
        prompt=prompt,
        image_base64=pages[0].image_base64,
        image_mime_type=pages[0].image_mime_type,
        function_definition=function_definition,
    )

    docs = response.get("documents", [])
    normalized: list[dict] = []
    for doc in docs:
        name = str(doc.get("doc_name", "document")).strip() or "document"
        indexes = [int(i) for i in doc.get("page_index", [])]
        if indexes:
            normalized.append({"doc_name": name, "page_index": indexes})

    if normalized:
        return normalized

    return [{"doc_name": "document_1", "page_index": [p.page_index for p in pages]}]
