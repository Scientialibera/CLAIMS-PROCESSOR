from __future__ import annotations

import json
import logging
import time
from contextlib import contextmanager
from typing import Any


@contextmanager
def timed_step():
    """Context manager that measures wall-clock elapsed milliseconds."""
    start = time.perf_counter()
    result = {"elapsed_ms": 0}
    try:
        yield result
    finally:
        result["elapsed_ms"] = round((time.perf_counter() - start) * 1000)


def get_logger(name: str = 'claims.processor') -> logging.Logger:
    logger = logging.getLogger(name)
    if not logger.handlers:
        handler = logging.StreamHandler()
        handler.setFormatter(logging.Formatter('%(asctime)s %(levelname)s %(message)s'))
        logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    return logger


def log_event(logger: logging.Logger, event: str, correlation_id: str, **kwargs: Any) -> None:
    payload = {'event': event, 'correlation_id': correlation_id, **kwargs}
    logger.info(json.dumps(payload, default=str))
