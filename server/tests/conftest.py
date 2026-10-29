import json

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.provider import MockProvider

WITCH_PROFILE = {
    "id": "witch", "name": "Witch", "personality": "observant, dry humor",
    "speaking_style": "brief, wry", "background": "elderly herbalist",
    "current_situation": "Tending an unusual garden", "starting_relationship": "familiar acquaintance",
}


def empty_memory(cid, revision=0):
    return {"schema_version": 1, "character_id": cid, "revision": revision,
            "last_processed_event_id": None, "facts": [], "ongoing": [], "experiences": []}


def msg(eid, speaker, text, audience=("player", "witch"), addressee="player"):
    return {"event_id": eid, "speaker": speaker, "addressee": addressee,
            "audience": list(audience), "text": text}


@pytest.fixture
def client():
    MockProvider.chunk_delay = 0
    app = create_app(Settings(mode="mock", base_url="", model="", api_key=""))
    return TestClient(app)


def read_events(resp):
    return [json.loads(line) for line in resp.text.splitlines() if line.strip()]
