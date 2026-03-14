import json
from pathlib import Path


def test_classification_function_has_database_enum():
    fn = json.loads(Path('src/function_definitions/classification/classify_doc_v1.json').read_text(encoding='utf-8'))
    enum_values = fn['parameters']['properties']['database']['enum']
    assert 'cosmos' in enum_values
    assert 'index' in enum_values
