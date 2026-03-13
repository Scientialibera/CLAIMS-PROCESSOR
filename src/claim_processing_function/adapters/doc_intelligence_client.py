from __future__ import annotations

from azure.ai.formrecognizer import DocumentAnalysisClient

from src.common.auth.credentials import get_credential


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
