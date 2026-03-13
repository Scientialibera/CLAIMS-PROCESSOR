from src.claim_update_function.updater.parse_update import parse_update


def test_parse_update_requires_fields():
    payload = {'claim_id': 'c1', 'record_id': 'r1', 'fields': {'a': 1}}
    assert parse_update(payload)['record_id'] == 'r1'
