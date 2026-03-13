from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

from src.claim_processing_function.adapters.cosmos_client import CosmosAdapter
from src.claim_processing_function.adapters.search_client import SearchAdapter


def _chunk_text(text: str, max_chars: int = 1800) -> list[str]:
    if not text:
        return []
    chunks: list[str] = []
    start = 0
    while start < len(text):
        chunks.append(text[start : start + max_chars])
        start += max_chars
    return chunks


def persist_outputs(
    claim_id: str,
    blob_path: str,
    etag: str,
    processed: list[dict],
    settings,
    *,
    status: str = "processed",
) -> None:
    cosmos = CosmosAdapter(
        endpoint=settings.cosmos_endpoint,
        database_name=settings.cosmos_database,
        ledger_container=settings.cosmos_ledger_container,
        records_container=settings.cosmos_records_container,
    )
    search = SearchAdapter(endpoint=settings.search_endpoint, index_name=settings.search_index)

    now = datetime.now(UTC).isoformat()
    search_docs: list[dict] = []

    for idx, item in enumerate(processed):
        record_id = f"{claim_id}:{etag}:{idx}:{uuid4().hex[:8]}"
        segment_text = str(item.get("segment", ""))
        fields = item.get("fields", {})
        doc_type = item.get("document_type", "unknown")

        record = {
            "id": record_id,
            "claim_id": claim_id,
            "blob_path": blob_path,
            "etag": etag,
            "document_type": doc_type,
            "content": segment_text,
            "extracted_fields": fields,
            "status": status,
            "created_at": now,
            "updated_at": now,
            "pipeline_version": settings.pipeline_version,
        }
        cosmos.upsert_record(record)

        for cidx, chunk in enumerate(_chunk_text(segment_text)):
            search_docs.append(
                {
                    "id": f"{record_id}:{cidx}",
                    "claim_id": claim_id,
                    "document_id": record_id,
                    "chunk_id": str(cidx),
                    "document_name": blob_path.split("/")[-1],
                    "content": chunk,
                    "document_summary": fields.get("summary", ""),
                    "created_at": now,
                }
            )

    search.upload_documents(search_docs)
    cosmos.upsert_ledger(
        claim_id=claim_id,
        blob_path=blob_path,
        etag=etag,
        pipeline_version=settings.pipeline_version,
        status=status,
        metadata={"segment_count": len(processed)},
    )
