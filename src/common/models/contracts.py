from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field


class ReadyEvent(BaseModel):
    claim_id: str
    trigger: Literal['ready'] = 'ready'
    correlation_id: str


class DocumentRef(BaseModel):
    blob_path: str
    content_type: str
    etag: str


class ProcessingRecord(BaseModel):
    claim_id: str
    document_id: str
    chunk_id: str | None = None
    document_name: str
    content: str
    document_summary: str | None = None
    created_at: str


class LedgerEntry(BaseModel):
    claim_id: str
    blob_path: str
    etag: str
    pipeline_version: str
    status: str
    processed_at: str
    metadata: dict[str, Any] = Field(default_factory=dict)
