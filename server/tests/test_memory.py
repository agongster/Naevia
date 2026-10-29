import pytest

from app.memory import MemoryValidationError, validate_proposal
from app.schemas import Memory, MemoryUpdateRequest
from conftest import empty_memory, msg


def update_body(**over):
    body = {"request_id": "u1", "character_id": "witch", "base_revision": 0,
            "memory": empty_memory("witch"),
            "new_events": [msg("e1", "player", "My exam is on Friday."),
                           msg("e2", "witch", "Then rest on Thursday.")]}
    body.update(over)
    return body


def proposal(revision=1, cursor="e2", sources=("e1",), cid="witch", text="Player's exam is Friday"):
    mem = empty_memory(cid, revision)
    mem["last_processed_event_id"] = cursor
    mem["facts"] = [{"id": "f1", "text": text, "source_event_ids": list(sources),
                     "learned_from": "player", "share_scope": "private"}]
    return Memory.model_validate(mem)


def req(**over):
    return MemoryUpdateRequest.model_validate(update_body(**over))


def test_valid_proposal_accepted():
    assert validate_proposal(req(), proposal()).revision == 1


@pytest.mark.parametrize("bad, why", [
    (dict(revision=2), "revision"),
    (dict(revision=0), "revision"),
    (dict(cid="blacksmith"), "another character"),
    (dict(sources=("e99",)), "unknown events"),
    (dict(cursor="e1"), "cursor"),
    (dict(text="x" * 400), None),
])
def test_invalid_proposals_rejected(bad, why):
    if why is None:  # single oversized entry is caught by the schema itself
        with pytest.raises(ValueError):
            Memory.model_validate({**proposal().model_dump(), "facts": [
                {"id": "f1", "text": "x" * 401, "source_event_ids": ["e1"],
                 "learned_from": "player", "share_scope": "private"}]})
        return
    with pytest.raises(MemoryValidationError, match=why):
        validate_proposal(req(), proposal(**bad))


def test_rejects_event_character_did_not_hear():
    events = [msg("e1", "player", "Only for the blacksmith", audience=["player", "blacksmith"])]
    with pytest.raises(MemoryValidationError, match="not heard"):
        validate_proposal(req(new_events=events), proposal(cursor="e1"))


def test_previously_validated_sources_are_allowed():
    old = proposal(revision=0, cursor="e0", sources=("e0",)).model_dump()
    p = proposal(revision=1, cursor="e2", sources=("e0",))
    assert validate_proposal(req(memory=old), p)


def test_total_text_cap():
    p = proposal()
    p.facts = [p.facts[0].model_copy(update={"id": f"f{i}", "text": "y" * 390}) for i in range(8)]
    with pytest.raises(MemoryValidationError, match="cap"):
        validate_proposal(req(), p)


def test_endpoint_mock_update_increments_revision_and_cursor(client):
    resp = client.post("/v1/memory/update", json=update_body())
    assert resp.status_code == 200
    mem = resp.json()["memory"]
    assert mem["revision"] == 1 and mem["last_processed_event_id"] == "e2"
    assert mem["experiences"][0]["source_event_ids"] == ["e1"]
    assert mem["experiences"][0]["share_scope"] == "private"


def test_endpoint_rejects_stale_base_revision(client):
    resp = client.post("/v1/memory/update", json=update_body(base_revision=3))
    assert resp.status_code == 422


def test_group_events_become_shared(client):
    group = ["player", "witch", "blacksmith"]
    body = update_body(new_events=[msg("e5", "blacksmith", "I finally fixed the old bellows.", audience=group)])
    exp = client.post("/v1/memory/update", json=body).json()["memory"]["experiences"][0]
    assert exp["share_scope"] == "shared" and exp["learned_from"] == "blacksmith"
