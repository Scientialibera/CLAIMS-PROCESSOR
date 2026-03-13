from __future__ import annotations

import json

from azure.servicebus import ServiceBusClient, ServiceBusMessage

from src.common.auth.credentials import get_credential


class FabricWriteQueueAdapter:
    def __init__(self, namespace_fqdn: str, queue_name: str) -> None:
        self._namespace_fqdn = namespace_fqdn
        self._queue_name = queue_name

    def enqueue_raw(self, payload: dict, session_id: str | None = None) -> None:
        message = ServiceBusMessage(json.dumps(payload), session_id=session_id)
        with ServiceBusClient(self._namespace_fqdn, credential=get_credential()) as client:
            with client.get_queue_sender(self._queue_name) as sender:
                sender.send_messages(message)
