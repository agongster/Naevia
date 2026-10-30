from conftest import WITCH_PROFILE, empty_memory, msg, read_events


def chat_body(**over):
    body = {
        "request_id": "r1", "conversation_id": "c1", "speaker_id": "witch",
        "participants": ["player", "witch"], "profile": WITCH_PROFILE,
        "memory": empty_memory("witch"),
        "recent_messages": [msg("e1", "player", "I have exams next week.")],
        "scene_context": "pigeon messenger",
    }
    body.update(over)
    return body


def test_health_reports_mock(client):
    assert client.get("/health").json() == {"status": "ok", "mode": "mock"}


def test_mock_stream_is_ndjson_ending_in_done(client):
    resp = client.post("/v1/chat", json=chat_body())
    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("application/x-ndjson")
    events = read_events(resp)
    assert all(e["request_id"] == "r1" for e in events)
    assert [e["type"] for e in events[:-1]] == ["text_delta"] * (len(events) - 1)
    assert events[-1] == {"type": "done", "request_id": "r1", "speaker_id": "witch", "addressee": "player"}
    text = "".join(e["text"] for e in events[:-1])
    assert "exams next week" in text


def test_mock_is_deterministic(client):
    a = client.post("/v1/chat", json=chat_body()).text
    b = client.post("/v1/chat", json=chat_body()).text
    assert a == b


def test_mock_reply_recalls_memory(client):
    memory = empty_memory("witch", revision=1)
    memory["experiences"] = [{"id": "m1_0", "text": "player said: I keep bees.", "source_event_ids": ["e0"],
                              "learned_from": "player", "share_scope": "private"}]
    text = "".join(e.get("text", "") for e in read_events(client.post("/v1/chat", json=chat_body(memory=memory))))
    assert "I remember: \"player said: I keep bees.\"" in text


def test_group_marker_is_stripped_and_routed(client):
    body = chat_body(participants=["player", "witch", "blacksmith"],
                     recent_messages=[msg("e1", "player", "I made the Dean's List!",
                                          audience=["player", "witch", "blacksmith"])])
    events = read_events(client.post("/v1/chat", json=body))
    text = "".join(e["text"] for e in events if e["type"] == "text_delta")
    assert "@to:" not in text
    assert events[-1]["addressee"] == "blacksmith"


def test_rejects_speaker_not_participant(client):
    assert client.post("/v1/chat", json=chat_body(speaker_id="blacksmith")).status_code == 422


def test_rejects_memory_of_other_character(client):
    resp = client.post("/v1/chat", json=chat_body(memory=empty_memory("blacksmith")))
    assert resp.status_code == 422


def test_rejects_more_than_twelve_messages(client):
    msgs = [msg(f"e{i}", "player", "hi") for i in range(13)]
    assert client.post("/v1/chat", json=chat_body(recent_messages=msgs)).status_code == 422
