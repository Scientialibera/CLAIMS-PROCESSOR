from __future__ import annotations

import json
import logging

from src.common.config.settings import get_settings
from src.common.logging.telemetry import log_event
from src.common.models.contracts import ReadyEvent
from src.processing_function.adapters.fabric_write_queue_client import FabricWriteQueueAdapter


def handle_claim_ready(message_body: bytes, logger: logging.Logger) -> None:
    settings = get_settings()
    payload = ReadyEvent.model_validate(json.loads(message_body.decode('utf-8')))

    queue = FabricWriteQueueAdapter(
        namespace_fqdn=settings.servicebus_namespace_fqdn,
        queue_name=settings.processing_queue_name,
    )
    queue.enqueue_raw(
        {
            'claim_id': payload.claim_id,
            'correlation_id': payload.correlation_id,
            'trigger': payload.trigger,
        },
        session_id=payload.claim_id,
    )
    log_event(logger, 'claim_intake_enqueued', payload.correlation_id, claim_id=payload.claim_id)
