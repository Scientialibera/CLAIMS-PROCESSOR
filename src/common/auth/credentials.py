from __future__ import annotations

from functools import lru_cache

from azure.identity import DefaultAzureCredential


@lru_cache(maxsize=1)
def get_credential() -> DefaultAzureCredential:
    return DefaultAzureCredential(exclude_interactive_browser_credential=True)


def get_access_token(scope: str) -> str:
    return get_credential().get_token(scope).token
