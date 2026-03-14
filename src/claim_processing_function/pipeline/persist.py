from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

from src.claim_processing_function.adapters.cosmos_client import CosmosAdapter
from src.claim_processing_function.adapters.search_client import SearchAdapter


def _estimate_tokens(text: str) -> int:
    return max(1, len(text) // 4)


def _chunk_pages_without_splitting(page_texts: list[str], max_tokens: int) -> list[str]:
    chunks: list[str] = []
    current_pages: list[str] = []
    current_tokens = 0

    for page_text in page_texts:
        page_tokens = _estimate_tokens(page_text)
        if current_pages and current_tokens + page_tokens > max_tokens:
            chunks.append("\n\n".join(current_pages))
            current_pages = [page_text]
            current_tokens = page_tokens
        else:
            current_pages.append(page_text)
            current_tokens += page_tokens

    if current_pages:
        chunks.append("\n\n".join(current_pages))

    return chunks


def persist_outputs(
    claim_id: str,
    blob_path: str,
    etag: str,
    processed_docs: list[dict],
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

    for idx, item in enumerate(processed_docs):
        record_id = f"{claim_id}:{etag}:{idx}:{uuid4().hex[:8]}"
        segment_text = str(item.get("full_text", ""))
        fields = item.get("fields", {})
        doc_type = item.get("document_type", "unknown")
        db_target = item.get("database", "cosmos")
        page_texts = item.get("page_texts", [])

        record = {
            "id": record_id,
            "claim_id": claim_id,
            "blob_path": blob_path,
            "etag": etag,
            "document_type": doc_type,
            "database_target": db_target,
            "content": segment_text,
            "extracted_fields": fields,
            "document_summary": item.get("summary", ""),
            "status": status,
            "created_at": now,
            "updated_at": now,
            "pipeline_version": settings.pipeline_version,
        }
        cosmos.upsert_record(record)

        if db_target == "index":
            chunks = _chunk_pages_without_splitting(
                page_texts if page_texts else [segment_text],
                settings.max_index_chunk_tokens,
            )
            for cidx, chunk in enumerate(chunks):
                search_docs.append(
                    {
                        "id": f"{record_id}:{cidx}",
                        "claim_id": claim_id,
                        "document_id": record_id,
                        "chunk_id": str(cidx),
                        "document_name": item.get("doc_name", blob_path.split("/")[-1]),
                        "content": chunk,
                        "document_summary": item.get("summary", ""),
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
        metadata={"doc_count": len(processed_docs), "indexed_chunk_count": len(search_docs)},
    )
