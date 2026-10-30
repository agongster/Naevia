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


def test_marker_on_same_line_is_stripped():
    # Seen live from gpt-4o-mini in a private chat.
    assert feed_all(["@to:player Ah, nerves", " can be like weeds."]) == ("Ah, nerves can be like weeds.", "player")


def test_same_line_marker_to_other_character():
    assert feed_all(["@to:blacksmith What", " do you think?"]) == ("What do you think?", "blacksmith")


def test_leading_ellipsis_line_before_reply_is_dropped():
    # Seen live in a group chat: "...\n\n@to:player That's quite the accomplishment."
    assert feed_all(["...", "\n\n@to:player That's", " quite something."]) == ("That's quite something.", "player")


def test_ellipsis_alone_is_kept_as_decline():
    assert feed_all(["..."]) == ("...", "player")
    assert feed_all(["…"]) == ("…", "player")


def test_ellipsis_starting_a_sentence_passes_through():
    assert feed_all(["...well, maybe."]) == ("...well, maybe.", "player")


def test_private_prompt_has_no_marker_instructions():
    system = build_chat_messages(request(["player", "witch"], []))[0]["content"]
    assert "@to:" not in system


def test_group_prompt_explains_marker_and_memory_sources():
    system = build_chat_messages(request(["player", "witch", "blacksmith"], []))[0]["content"]
    assert "@to:blacksmith" in system
    assert "Player likes plums (the player told you)" in system


def test_copied_history_label_is_stripped():
    # Seen live: "[witch to player] Rest is crucial..."
    assert feed_all(["[witch to ", "player] Rest is", " crucial."]) == ("Rest is crucial.", "player")


def test_bracketed_text_that_is_not_a_label_passes_through():
    assert feed_all(["[sighs] Fine."]) == ("[sighs] Fine.", "player")


def test_own_lines_are_unlabeled_in_history():
    msgs = build_chat_messages(request(["player", "witch"], [msg("e1", "player", "Hi"), msg("e2", "witch", "Hello.")]))
    assert msgs[1] == {"role": "user", "content": "Hi"} and msgs[2] == {"role": "assistant", "content": "Hello."}
