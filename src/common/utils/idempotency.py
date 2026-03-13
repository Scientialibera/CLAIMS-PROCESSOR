from __future__ import annotations

import hashlib


def build_document_key(claim_id: str, blob_path: str, etag: str) -> str:
    return hashlib.sha256(f'{claim_id}|{blob_path}|{etag}'.encode('utf-8')).hexdigest()
