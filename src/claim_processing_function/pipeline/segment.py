from __future__ import annotations

from src.claim_processing_function.adapters.openai_client import AzureOpenAIAdapter


def segment_document(text: str, prompt: str, client: AzureOpenAIAdapter) -> list[str]:
    if not text.strip():
        return []
    payload = client.segment(text, prompt)
    sections = payload.get('sections', [])
    extracted = [s.get('text', '').strip() for s in sections if s.get('text')]
    if extracted:
        return extracted
    return [text]
