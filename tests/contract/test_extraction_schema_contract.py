import json
from pathlib import Path


def test_extraction_schema_has_required_fields():
    schema = json.loads(Path('src/schemas/extraction/claim_core_v1.json').read_text(encoding='utf-8'))
    assert 'required_fields' in schema
