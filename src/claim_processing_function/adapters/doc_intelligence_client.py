from __future__ import annotations

import base64
from dataclasses import dataclass

from azure.ai.formrecognizer import DocumentAnalysisClient

from src.common.auth.credentials import get_credential


@dataclass(frozen=True)
class PagePayload:
    page_index: int
    text: str
    image_base64: str | None = None
    image_mime_type: str | None = None
    source_name: str | None = None


class DocumentIntelligenceAdapter:
    def __init__(self, endpoint: str) -> None:
        self._client = DocumentAnalysisClient(endpoint=endpoint, credential=get_credential())

    def extract_text(self, content: bytes) -> str:
        try:
            poller = self._client.begin_analyze_document('prebuilt-read', document=content)
            result = poller.result()
            return '\n'.join(line.content for page in result.pages for line in page.lines)
        except Exception:
            # Fallback for text-like files to keep pipeline resilient.
            return content.decode("utf-8", errors="ignore")

    def extract_pages(self, content: bytes, content_type: str, source_name: str) -> list[PagePayload]:
        try:
            poller = self._client.begin_analyze_document('prebuilt-read', document=content)
            result = poller.result()
            pages: list[PagePayload] = []
            for idx, page in enumerate(result.pages):
                page_text = '\n'.join(line.content for line in page.lines)
                pages.append(
                    PagePayload(
                        page_index=idx,
                        text=page_text,
                        image_base64=None,
                        image_mime_type=None,
                        source_name=source_name,
                    )
                )
            if pages:
                return pages
        except Exception:
            pass

        image_payload: str | None = None
        if content_type.lower() in {"image/png", "image/jpeg", "image/jpg", "image/tiff"}:
            image_payload = base64.b64encode(content).decode("utf-8")

        return [
            PagePayload(
                page_index=0,
                text=content.decode("utf-8", errors="ignore"),
                image_base64=image_payload,
                image_mime_type=content_type if image_payload else None,
                source_name=source_name,
            )
        ]
