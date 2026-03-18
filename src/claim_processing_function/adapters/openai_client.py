from __future__ import annotations

import json
from collections.abc import Sequence
from typing import Any

import requests

from src.common.auth.credentials import get_access_token


class AzureOpenAIAdapter:
    AOAI_SCOPE = 'https://cognitiveservices.azure.com/.default'

    def __init__(self, settings) -> None:
        self._settings = settings

    def _chat(
        self,
        deployment: str,
        prompt: str,
        content: str,
        *,
        image_base64: str | None = None,
        image_mime_type: str | None = None,
        function_definition: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        token = get_access_token(self.AOAI_SCOPE)
        url = (
            f"{self._settings.aoai_endpoint}/openai/deployments/{deployment}/chat/completions"
            f"?api-version={self._settings.aoai_api_version}"
        )

        user_content: Sequence[dict[str, Any]] | str
        if image_base64 and image_mime_type:
            user_content = [
                {"type": "text", "text": content},
                {
                    "type": "image_url",
                    "image_url": {"url": f"data:{image_mime_type};base64,{image_base64}"},
                },
            ]
        else:
            user_content = content

        body: dict[str, Any] = {
            'messages': [
                {'role': 'system', 'content': prompt},
                {'role': 'user', 'content': user_content},
            ],
            'response_format': {'type': 'json_object'},
        }
        if self._settings.profile.temperature is not None:
            body['temperature'] = self._settings.profile.temperature
        if self._settings.profile.max_completion_tokens:
            body['max_completion_tokens'] = self._settings.profile.max_completion_tokens
        if function_definition:
            body["tools"] = [{"type": "function", "function": function_definition}]
            body["tool_choice"] = {"type": "function", "function": {"name": function_definition["name"]}}

        response = requests.post(url, json=body, headers={'Authorization': f'Bearer {token}'}, timeout=60)
        response.raise_for_status()
        msg = response.json()['choices'][0]['message']
        content_json = msg.get('content')
        if not content_json and msg.get("tool_calls"):
            args = msg["tool_calls"][0]["function"]["arguments"]
            return json.loads(args)
        try:
            return json.loads(content_json)
        except Exception as exc:
            raise ValueError(f"Model response is not valid JSON: {content_json}") from exc

    def segment(
        self,
        text: str,
        prompt: str,
        *,
        image_base64: str | None = None,
        image_mime_type: str | None = None,
        function_definition: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        return self._chat(
            self._settings.profile.segment_model,
            prompt,
            text,
            image_base64=image_base64,
            image_mime_type=image_mime_type,
            function_definition=function_definition,
        )

    def classify(
        self,
        text: str,
        prompt: str,
        *,
        image_base64: str | None = None,
        image_mime_type: str | None = None,
        function_definition: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        return self._chat(
            self._settings.profile.classify_model,
            prompt,
            text,
            image_base64=image_base64,
            image_mime_type=image_mime_type,
            function_definition=function_definition,
        )

    def extract(
        self,
        text: str,
        prompt: str,
        *,
        image_base64: str | None = None,
        image_mime_type: str | None = None,
        function_definition: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        return self._chat(
            self._settings.profile.extract_model,
            prompt,
            text,
            image_base64=image_base64,
            image_mime_type=image_mime_type,
            function_definition=function_definition,
        )

    def embed(self, text: str) -> list[float]:
        token = get_access_token(self.AOAI_SCOPE)
        url = (
            f"{self._settings.aoai_endpoint}/openai/deployments/{self._settings.aoai_embedding_deployment}/embeddings"
            f"?api-version={self._settings.aoai_api_version}"
        )
        response = requests.post(
            url,
            json={"input": text},
            headers={'Authorization': f'Bearer {token}'},
            timeout=60,
        )
        response.raise_for_status()
        data = response.json()["data"][0]["embedding"]
        return [float(v) for v in data]
