from __future__ import annotations

import json

import azure.functions as func

from src.claim_intake_function.handler import handle_claim_ready
from src.claim_processing_function.handler import process_claim
from src.claim_update_function.handler import apply_claim_update
from src.common.logging.telemetry import get_logger

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)
logger = get_logger()


@app.function_name(name='ClaimIntake')
@app.service_bus_queue_trigger(
    arg_name='msg',
    queue_name='%SERVICEBUS_READY_QUEUE_NAME%',
    connection='SERVICEBUS_CONNECTION',
)
def claim_intake_trigger(msg: func.ServiceBusMessage) -> None:
    handle_claim_ready(msg.get_body(), logger)


@app.function_name(name='ClaimProcessing')
@app.service_bus_queue_trigger(
    arg_name='msg',
    queue_name='%SERVICEBUS_PROCESSING_QUEUE_NAME%',
    connection='SERVICEBUS_CONNECTION',
    is_sessions_enabled=True,
)
def claim_processing_trigger(msg: func.ServiceBusMessage) -> None:
    process_claim(msg.get_body(), logger)


@app.function_name(name='ApplyClaimUpdate')
@app.route(route='apply-claim-update', methods=['POST'])
def apply_claim_update_trigger(req: func.HttpRequest) -> func.HttpResponse:
    payload = req.get_json()
    result = apply_claim_update(payload, logger)
    return func.HttpResponse(body=json.dumps(result), status_code=200, mimetype='application/json')
