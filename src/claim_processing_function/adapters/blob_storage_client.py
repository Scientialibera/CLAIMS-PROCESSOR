from __future__ import annotations

from dataclasses import dataclass

from azure.storage.blob import BlobServiceClient

from src.common.auth.credentials import get_credential


@dataclass(frozen=True)
class BlobDocument:
    blob_path: str
    etag: str
    content_type: str


class BlobStorageAdapter:
    def __init__(self, account_url: str, container_name: str) -> None:
        self._service = BlobServiceClient(account_url=account_url, credential=get_credential())
        self._container = self._service.get_container_client(container_name)

    def list_claim_documents(self, claim_id: str, prefix: str = "") -> list[BlobDocument]:
        claim_prefix = f"{prefix}{claim_id}/" if prefix else f"{claim_id}/"
        allowed_ext = {".pdf", ".jpg", ".jpeg", ".tiff", ".tif", ".png"}
        docs: list[BlobDocument] = []
        for item in self._container.list_blobs(name_starts_with=claim_prefix):
            name = item.name
            if name.endswith("/_READY.json") or name.endswith("_READY.json"):
                continue
            if name.endswith("/"):
                continue
            lower_name = name.lower()
            if not any(lower_name.endswith(ext) for ext in allowed_ext):
                continue
            docs.append(
                BlobDocument(
                    blob_path=name,
                    etag=str(item.etag).strip('"'),
                    content_type=str(item.content_settings.content_type or "application/octet-stream"),
                )
            )
        return docs

    def download_bytes(self, blob_path: str) -> bytes:
        client = self._container.get_blob_client(blob_path)
        return client.download_blob().readall()
