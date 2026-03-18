from __future__ import annotations

from functools import lru_cache

from azure.identity import DefaultAzureCredential, get_bearer_token_provider


@lru_cache(maxsize=1)
def get_credential() -> DefaultAzureCredential:
    return DefaultAzureCredential(exclude_interactive_browser_credential=True)


def get_access_token(scope: str) -> str:
    return get_credential().get_token(scope).token


@lru_cache(maxsize=1)
def get_aoai_token_provider():
    """Pre-built token provider for Azure OpenAI SDK authentication."""
    return get_bearer_token_provider(
        get_credential(), "https://cognitiveservices.azure.com/.default"
    )
