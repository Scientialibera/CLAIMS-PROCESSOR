from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from azure.cosmos import CosmosClient, PartitionKey

from src.common.auth.credentials import get_credential


class CosmosAdapter:
    def __init__(self, endpoint: str, database_name: str, ledger_container: str, records_container: str) -> None:
        self._client = CosmosClient(url=endpoint, credential=get_credential())
        self._db = self._client.create_database_if_not_exists(id=database_name)
        self._ledger = self._db.create_container_if_not_exists(
            id=ledger_container,
            partition_key=PartitionKey(path="/claim_id"),
            offer_throughput=400,
        )
        self._records = self._db.create_container_if_not_exists(
            id=records_container,
            partition_key=PartitionKey(path="/claim_id"),
            offer_throughput=400,
        )

    def ledger_key(self, claim_id: str, blob_path: str, etag: str, pipeline_version: str) -> str:
        return f"{claim_id}|{blob_path}|{etag}|{pipeline_version}"

    def is_already_processed(self, claim_id: str, blob_path: str, etag: str, pipeline_version: str) -> bool:
        doc_id = self.ledger_key(claim_id, blob_path, etag, pipeline_version)
        try:
            self._ledger.read_item(item=doc_id, partition_key=claim_id)
            return True
        except Exception:
            return False

    def upsert_ledger(
        self,
        claim_id: str,
        blob_path: str,
        etag: str,
        pipeline_version: str,
        status: str,
        metadata: dict[str, Any] | None = None,
    ) -> None:
        item = {
            "id": self.ledger_key(claim_id, blob_path, etag, pipeline_version),
            "claim_id": claim_id,
            "blob_path": blob_path,
            "etag": etag,
            "pipeline_version": pipeline_version,
            "status": status,
            "processed_at": datetime.now(UTC).isoformat(),
            "metadata": metadata or {},
        }
        self._ledger.upsert_item(item)

    def upsert_record(self, item: dict[str, Any]) -> None:
        self._records.upsert_item(item)

    def patch_record(self, claim_id: str, record_id: str, fields: dict[str, Any]) -> None:
        operations = [{"op": "add", "path": f"/{k}", "value": v} for k, v in fields.items()]
        operations.append({"op": "add", "path": "/updated_at", "value": datetime.now(UTC).isoformat()})
        self._records.patch_item(item=record_id, partition_key=claim_id, patch_operations=operations)
