from __future__ import annotations

from datetime import UTC, datetime

from src.claim_processing_function.adapters.cosmos_client import CosmosAdapter
from src.common.config.settings import get_settings


def apply_update(payload: dict) -> None:
    settings = get_settings()
    cosmos = CosmosAdapter(
        endpoint=settings.cosmos_endpoint,
        database_name=settings.cosmos_database,
        ledger_container=settings.cosmos_ledger_container,
        records_container=settings.cosmos_records_container,
    )

    updates = dict(payload["fields"])
    updates["status"] = payload.get("status", "updated")
    updates["updated_by_flow"] = "ApplyClaimUpdate"
    updates["updated_at"] = datetime.now(UTC).isoformat()

    cosmos.patch_record(
        claim_id=payload["claim_id"],
        record_id=payload["record_id"],
        fields=updates,
    )
