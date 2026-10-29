from app.prompts import MarkerFilter, build_chat_messages
from app.schemas import ChatRequest
from conftest import WITCH_PROFILE, empty_memory, msg


def entry(eid, text, scope):
    return {"id": eid, "text": text, "source_event_ids": ["e1"], "learned_from": "player", "share_scope": scope}


def request(participants, recent):
    mem = empty_memory("witch")
    mem["facts"] = [entry("f1", "Player's exam is on Friday", "private"),
                    entry("f2", "Player likes plums", "shared")]
    return ChatRequest.model_validate({
        "request_id": "r", "conversation_id": "c", "speaker_id": "witch",
        "participants": participants, "profile": WITCH_PROFILE, "memory": mem,
        "recent_messages": recent,
    })


def test_private_prompt_includes_private_memory():
    system = build_chat_messages(request(["player", "witch"], []))[0]["content"]
    assert "exam is on Friday" in system and "plums" in system


def test_group_prompt_withholds_private_memory():
    system = build_chat_messages(request(["player", "witch", "blacksmith"], []))[0]["content"]
    assert "exam is on Friday" not in system
    assert "plums" in system


def test_prompt_only_includes_heard_messages():
    recent = [msg("e1", "player", "secret for blacksmith", audience=["player", "blacksmith"]),
              msg("e2", "player", "hello witch")]
    joined = " ".join(m["content"] for m in build_chat_messages(request(["player", "witch"], recent)))
    assert "secret for blacksmith" not in joined
    assert "hello witch" in joined


def test_prompt_order_profile_before_memory_before_scene():
    system = build_chat_messages(request(["player", "witch"], []))[0]["content"]
    assert system.index("Profile:") < system.index("What you remember") < system.index("Scene:")


def feed_all(chunks, participants=("player", "witch", "blacksmith")):
    f = MarkerFilter("witch", list(participants))
    out = "".join(f.feed(c) for c in chunks) + f.flush()
    return out, f.addressee


def test_marker_split_across_chunks():
    assert feed_all(["@t", "o:black", "smith\nHow's ", "the tool?"]) == ("How's the tool?", "blacksmith")


def test_invalid_marker_defaults_to_player():
    assert feed_all(["@to:dragon\nHi."]) == ("Hi.", "player")


def test_no_marker_passes_text_through():
    assert feed_all(["Hello", " there."]) == ("Hello there.", "player")


def test_marker_cannot_target_self():
    assert feed_all(["@to:witch\nHm."]) == ("Hm.", "player")
