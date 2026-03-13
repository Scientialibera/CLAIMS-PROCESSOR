from src.common.utils.validation import required_missing


def test_required_missing():
    payload = {'a': 1, 'b': ''}
    assert required_missing(payload, ['a', 'b', 'c']) == ['b', 'c']
