"""Environment configuration (SPEC 5.1). Values come from server/.env via uvicorn --env-file."""

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    mode: str
    base_url: str
    model: str
    api_key: str

    @classmethod
    def from_env(cls) -> "Settings":
        mode = os.environ.get("NAEVIA_MODEL_MODE", "mock").strip().lower()
        if mode not in ("mock", "live"):
            raise ValueError("NAEVIA_MODEL_MODE must be 'mock' or 'live'")
        settings = cls(
            mode=mode,
            base_url=os.environ.get("NAEVIA_PROVIDER_BASE_URL", ""),
            model=os.environ.get("NAEVIA_MODEL", ""),
            api_key=os.environ.get("NAEVIA_PROVIDER_API_KEY", ""),
        )
        if mode == "live" and not (settings.base_url and settings.model and settings.api_key):
            raise ValueError("live mode needs NAEVIA_PROVIDER_BASE_URL, NAEVIA_MODEL and NAEVIA_PROVIDER_API_KEY")
        return settings
