from __future__ import annotations

from azure.search.documents import SearchClient

from src.common.auth.credentials import get_credential


class SearchAdapter:
    def __init__(self, endpoint: str, index_name: str) -> None:
        self._client = SearchClient(endpoint=endpoint, index_name=index_name, credential=get_credential())

    def upload_documents(self, docs: list[dict]) -> None:
        if not docs:
            return
        self._client.upload_documents(documents=docs)
