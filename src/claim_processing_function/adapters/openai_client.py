from __future__ import annotations

import json
from typing import Any

import requests

from src.common.auth.credentials import get_access_token


class AzureOpenAIAdapter:
    AOAI_SCOPE = 'https://cognitiveservices.azure.com/.default'

    def __init__(self, settings) -> None:
        self._settings = settings

    def _chat(self, deployment: str, prompt: str, content: str) -> dict[str, Any]:
        token = get_access_token(self.AOAI_SCOPE)
        url = (
            f"{self._settings.aoai_endpoint}/openai/deployments/{deployment}/chat/completions"
            f"?api-version={self._settings.aoai_api_version}"
        )
        body = {
            'temperature': self._settings.profile.temperature,
            'max_tokens': self._settings.profile.max_tokens,
            'messages': [
                {'role': 'system', 'content': prompt},
                {'role': 'user', 'content': content},
            ],
            'response_format': {'type': 'json_object'},
        }
        response = requests.post(url, json=body, headers={'Authorization': f'Bearer {token}'}, timeout=60)
        response.raise_for_status()
        return json.loads(response.json()['choices'][0]['message']['content'])

    def segment(self, text: str, prompt: str) -> dict[str, Any]:
        return self._chat(self._settings.profile.segment_model, prompt, text)

    def classify(self, text: str, prompt: str) -> dict[str, Any]:
        return self._chat(self._settings.profile.classify_model, prompt, text)

    def extract(self, text: str, prompt: str) -> dict[str, Any]:
        return self._chat(self._settings.profile.extract_model, prompt, text)
