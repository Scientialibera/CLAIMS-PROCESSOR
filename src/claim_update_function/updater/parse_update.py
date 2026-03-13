from __future__ import annotations


def parse_update(payload: dict) -> dict:
    if 'claim_id' not in payload:
        raise ValueError('claim_id is required')
    if 'record_id' not in payload:
        raise ValueError('record_id is required')
    if 'fields' not in payload:
        raise ValueError('fields is required')
    if not isinstance(payload['fields'], dict):
        raise ValueError('fields must be an object')
    return payload
