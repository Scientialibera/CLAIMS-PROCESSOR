from __future__ import annotations


def required_missing(payload: dict, required_fields: list[str]) -> list[str]:
    missing: list[str] = []
    for field in required_fields:
        value = payload.get(field)
        if value in (None, '', [], {}):
            missing.append(field)
    return missing
