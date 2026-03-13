from __future__ import annotations


def parse_update(payload: dict) -> dict:
    if 'claim_id' not in payload:
        raise ValueError('claim_id is required')
    if 'fields' not in payload:
        raise ValueError('fields is required')
    return payload
