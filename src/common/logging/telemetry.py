from __future__ import annotations

import logging


def get_logger(name: str = 'claims.processor') -> logging.Logger:
    logger = logging.getLogger(name)
    if not logger.handlers:
        handler = logging.StreamHandler()
        handler.setFormatter(logging.Formatter('%(asctime)s %(levelname)s %(message)s'))
        logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    return logger


def log_event(logger: logging.Logger, event: str, correlation_id: str, **kwargs) -> None:
    payload = {'event': event, 'correlation_id': correlation_id, **kwargs}
    logger.info(payload)
