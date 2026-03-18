from __future__ import annotations

import base64
import json
import logging
from dataclasses import dataclass

from azure.ai.documentintelligence import DocumentIntelligenceClient
from azure.ai.documentintelligence.models import AnalyzeDocumentRequest

from src.common.auth.credentials import get_credential
from src.common.logging.telemetry import timed_step

_logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class PagePayload:
    page_index: int
    text: str
    image_base64: str | None = None
    image_mime_type: str | None = None
    source_name: str | None = None


class DocumentIntelligenceAdapter:
    def __init__(self, endpoint: str) -> None:
        self._client = DocumentIntelligenceClient(endpoint=endpoint, credential=get_credential())

    def extract_text(self, content: bytes) -> str:
        try:
            with timed_step() as t:
                poller = self._client.begin_analyze_document(
                    'prebuilt-read',
                    AnalyzeDocumentRequest(bytes_source=content),
                )
                result = poller.result()

            page_count = len(result.pages or [])
            _logger.info(json.dumps({
                "event": "doc_intelligence_call",
                "elapsed_ms": t["elapsed_ms"],
                "pages": page_count,
                "input_bytes": len(content),
            }, default=str))

            return '\n'.join(
                line.content
                for page in (result.pages or [])
                for line in (page.lines or [])
            )
        except Exception:
            return content.decode("utf-8", errors="ignore")

    def extract_pages(self, content: bytes, content_type: str, source_name: str) -> list[PagePayload]:
        image_payload: str | None = None
        normalized_content_type = content_type.lower()
        if normalized_content_type in {"image/png", "image/jpeg", "image/jpg", "image/tiff"}:
            image_payload = base64.b64encode(content).decode("utf-8")

        try:
            with timed_step() as t:
                poller = self._client.begin_analyze_document(
                    'prebuilt-read',
                    AnalyzeDocumentRequest(bytes_source=content),
                )
                result = poller.result()

            raw_pages = result.pages or []
            _logger.info(json.dumps({
                "event": "doc_intelligence_call",
                "elapsed_ms": t["elapsed_ms"],
                "pages": len(raw_pages),
                "input_bytes": len(content),
                "source_name": source_name,
            }, default=str))

            pages: list[PagePayload] = []
            for idx, page in enumerate(raw_pages):
                page_text = '\n'.join(line.content for line in (page.lines or []))
                pages.append(
                    PagePayload(
                        page_index=idx,
                        text=page_text,
                        image_base64=image_payload if idx == 0 else None,
                        image_mime_type=content_type if (image_payload and idx == 0) else None,
                        source_name=source_name,
                    )
                )
            if pages:
                return pages
        except Exception:
            pass

        return [
            PagePayload(
                page_index=0,
                text=content.decode("utf-8", errors="ignore"),
                image_base64=image_payload,
                image_mime_type=content_type if image_payload else None,
                source_name=source_name,
            )
        ]
