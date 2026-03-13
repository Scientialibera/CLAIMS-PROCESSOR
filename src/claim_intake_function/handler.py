from __future__ import annotations

import json
import logging

from src.common.config.settings import get_settings
from src.common.logging.telemetry import log_event
from src.common.models.contracts import ReadyEvent
from src.processing_function.adapters.fabric_write_queue_client import FabricWriteQueueAdapter


def _derive_claim_id(payload: ReadyEvent) -> str:
    if payload.claim_id:
        return payload.claim_id
    if payload.blob_path:
        normalized = payload.blob_path.strip("/")
        parts = normalized.split("/")
        if parts:
            return parts[-2] if parts[-1].lower() == "_ready.json" and len(parts) > 1 else parts[0]
    raise ValueError("Unable to determine claim_id from ready payload")


def handle_claim_ready(message_body: bytes, logger: logging.Logger) -> None:
    settings = get_settings()
    payload = ReadyEvent.model_validate(json.loads(message_body.decode('utf-8')))
    claim_id = _derive_claim_id(payload)

    queue = FabricWriteQueueAdapter(
        namespace_fqdn=settings.servicebus_namespace_fqdn,
        queue_name=settings.processing_queue_name,
    )
    queue.enqueue_raw(
        {
            'claim_id': claim_id,
            'correlation_id': payload.correlation_id,
            'trigger': payload.trigger,
        },
        session_id=claim_id,
    )
    log_event(logger, 'claim_intake_enqueued', payload.correlation_id, claim_id=claim_id)
