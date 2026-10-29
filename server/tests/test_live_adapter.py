import json

import httpx

from app.config import Settings
from app.main import create_app
from app.provider import LiveProvider
from conftest import read_events
from fastapi.testclient import TestClient
from test_chat import chat_body
from test_memory import proposal, update_body

SETTINGS = Settings(mode="live", base_url="https://example.test/v1/", model="m", api_key="k")


def sse(*deltas):
    lines = [f"data: {json.dumps({'choices': [{'delta': {'content': d}}]})}" for d in deltas]
    return ("\n\n".join(lines + ["data: [DONE]"]) + "\n\n").encode()


def live_client(handler):
    provider = LiveProvider(SETTINGS, transport=httpx.MockTransport(handler))
    return TestClient(create_app(SETTINGS, provider))


def test_live_stream_parses_sse_and_strips_marker():
    seen = {}

    def handler(request):
        seen["url"] = str(request.url)
        seen["auth"] = request.headers["authorization"]
        return httpx.Response(200, content=sse("@to:pla", "yer\nGood ", "luck."))

    events = read_events(live_client(handler).post("/v1/chat", json=chat_body()))
    assert seen == {"url": "https://example.test/v1/chat/completions", "auth": "Bearer k"}
    assert "".join(e["text"] for e in events if e["type"] == "text_delta") == "Good luck."
    assert events[-1]["type"] == "done"


def test_live_provider_http_error_becomes_error_event():
    events = read_events(live_client(lambda r: httpx.Response(401)).post("/v1/chat", json=chat_body()))
    assert events == [{"type": "error", "request_id": "r1", "message": "Provider returned HTTP 401"}]


def test_live_provider_unreachable_becomes_error_event():
    def handler(request):
        raise httpx.ConnectError("down")

    events = read_events(live_client(handler).post("/v1/chat", json=chat_body()))
    assert events[-1]["type"] == "error" and "reach" in events[-1]["message"]


def test_live_memory_update_validated():
    good = proposal().model_dump_json()

    def handler(request):
        return httpx.Response(200, json={"choices": [{"message": {"content": "```json\n" + good + "\n```"}}]})

    resp = live_client(handler).post("/v1/memory/update", json=update_body())
    assert resp.status_code == 200 and resp.json()["memory"]["revision"] == 1


def test_live_memory_update_rejects_invented_source():
    bad = proposal(sources=("e42",)).model_dump_json()
    handler = lambda r: httpx.Response(200, json={"choices": [{"message": {"content": bad}}]})
    resp = live_client(handler).post("/v1/memory/update", json=update_body())
    assert resp.status_code == 422 and "unknown events" in resp.json()["detail"]
