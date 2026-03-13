from __future__ import annotations

import logging

from src.claim_update_function.updater.apply_update import apply_update
from src.claim_update_function.updater.parse_update import parse_update
from src.common.logging.telemetry import log_event


def apply_claim_update(payload: dict, logger: logging.Logger) -> dict:
    parsed = parse_update(payload)
    apply_update(parsed)
    log_event(logger, 'claim_update_applied', parsed.get('correlation_id', parsed.get('claim_id', 'unknown')))
    return {'status': 'updated', 'claim_id': parsed['claim_id']}
