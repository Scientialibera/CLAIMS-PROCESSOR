from __future__ import annotations

import json
import os
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any

import yaml


@dataclass(frozen=True)
class ModelProfile:
    segment_model: str
    classify_model: str
    extract_model: str
    temperature: float
    max_tokens: int


@dataclass(frozen=True)
class AppSettings:
    ready_queue_name: str
    processing_queue_name: str
    servicebus_namespace_fqdn: str
    blob_account_url: str
    blob_container: str
    blob_claims_prefix: str
    cosmos_endpoint: str
    cosmos_database: str
    cosmos_ledger_container: str
    cosmos_records_container: str
    search_endpoint: str
    search_index: str
    pipeline_version: str
    docintel_endpoint: str
    aoai_endpoint: str
    aoai_api_version: str
    profile: ModelProfile
    extraction_schema: dict[str, Any]
    classification_schema: dict[str, Any]
    segment_prompt: str
    classify_prompt: str
    extract_prompt: str


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def _read_text(path: Path) -> str:
    return path.read_text(encoding='utf-8')


def _load_json(path: Path) -> dict[str, Any]:
    return json.loads(_read_text(path))


def _resolve(value: str) -> str:
    if value.startswith('${') and value.endswith('}'):
        return os.getenv(value[2:-1], '')
    return value


def _load_profile(name: str) -> ModelProfile:
    payload = yaml.safe_load(_read_text(_repo_root() / 'src' / 'model_profiles' / f'{name}.yaml'))
    return ModelProfile(
        segment_model=_resolve(payload['segment_model']),
        classify_model=_resolve(payload['classify_model']),
        extract_model=_resolve(payload['extract_model']),
        temperature=float(payload.get('temperature', 0.0)),
        max_tokens=int(payload.get('max_tokens', 2000)),
    )


@lru_cache(maxsize=1)
def get_settings() -> AppSettings:
    profile_name = os.getenv('ACTIVE_MODEL_PROFILE', 'default')
    extraction_name = os.getenv('ACTIVE_EXTRACTION_SCHEMA', 'claim_core_v1')
    classification_name = os.getenv('ACTIVE_CLASSIFICATION_SCHEMA', 'doc_types_v1')

    return AppSettings(
        ready_queue_name=os.getenv('SERVICEBUS_READY_QUEUE_NAME', 'q-claim-ready'),
        processing_queue_name=os.getenv('SERVICEBUS_PROCESSING_QUEUE_NAME', 'q-claim-process'),
        servicebus_namespace_fqdn=os.getenv('SERVICEBUS_NAMESPACE_FQDN', ''),
        blob_account_url=os.getenv('BLOB_ACCOUNT_URL', ''),
        blob_container=os.getenv('BLOB_CONTAINER', 'claims'),
        blob_claims_prefix=os.getenv('BLOB_CLAIMS_PREFIX', ''),
        cosmos_endpoint=os.getenv('COSMOS_ENDPOINT', ''),
        cosmos_database=os.getenv('COSMOS_DATABASE', 'claims'),
        cosmos_ledger_container=os.getenv('COSMOS_LEDGER_CONTAINER', 'processing_ledger'),
        cosmos_records_container=os.getenv('COSMOS_RECORDS_CONTAINER', 'processed_records'),
        search_endpoint=os.getenv('SEARCH_ENDPOINT', ''),
        search_index=os.getenv('SEARCH_INDEX', 'claims-index'),
        pipeline_version=os.getenv('PIPELINE_VERSION', 'v1'),
        docintel_endpoint=os.getenv('DOCINTEL_ENDPOINT', ''),
        aoai_endpoint=os.getenv('AOAI_ENDPOINT', ''),
        aoai_api_version=os.getenv('AOAI_API_VERSION', '2024-06-01'),
        profile=_load_profile(profile_name),
        extraction_schema=_load_json(_repo_root() / 'src' / 'schemas' / 'extraction' / f'{extraction_name}.json'),
        classification_schema=_load_json(_repo_root() / 'src' / 'schemas' / 'classification' / f'{classification_name}.json'),
        segment_prompt=_read_text(_repo_root() / 'src' / 'prompts' / 'segmentation' / 'segment_v1.txt'),
        classify_prompt=_read_text(_repo_root() / 'src' / 'prompts' / 'classification' / 'classify_v1.txt'),
        extract_prompt=_read_text(_repo_root() / 'src' / 'prompts' / 'extraction' / 'extract_v1.txt'),
    )
