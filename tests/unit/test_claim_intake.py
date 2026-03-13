from src.claim_intake_function.handler import _derive_claim_id
from src.common.models.contracts import ReadyEvent


def test_derive_claim_id_from_claim_id():
    payload = ReadyEvent(claim_id='claim_123', correlation_id='c1')
    assert _derive_claim_id(payload) == 'claim_123'


def test_derive_claim_id_from_blob_path():
    payload = ReadyEvent(blob_path='claims/claim_999/_READY.json', correlation_id='c2')
    assert _derive_claim_id(payload) == 'claim_999'
