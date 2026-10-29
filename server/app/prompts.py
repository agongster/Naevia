"""Prompt composition and recipient-marker handling (SPEC 4.3, 5.2, 5.3, 6.3)."""

import json

from .schemas import ChatRequest, Memory, MemoryUpdateRequest

CHARACTER_INSTRUCTIONS = """You are {name}, a character in Naevia, a small cozy pixel world.
Stay in character. Reply in one to three short sentences, as spoken dialogue only.
Respond to what was actually said. You may mention your own current life.
Do not flatter or praise by reflex, do not invent shared past events, and never
pressure the player to keep talking or guilt them for being away.
If you are speaking to someone other than the player, put a first line of the
exact form @to:<id> (one of: {others}) and then your reply. Otherwise just reply.
If you have nothing to add, reply with a single ellipsis."""

MEMORY_INSTRUCTIONS = """You maintain the private memory notes of {character_id}.
Return ONLY a JSON object: the full replacement memory with keys schema_version (1),
character_id, revision ({revision}), last_processed_event_id ("{cursor}"),
facts, ongoing, experiences. Each entry: id, text, source_event_ids, learned_from,
share_scope ("private" or "shared"). Keep valid existing entries, update changed
situations, merge duplicates, stay under {cap} characters of entry text in total.
Cite only event ids from the existing memory or the new events. Never invent events.
Things said in a private conversation are "private"; things said openly in a group are "shared".
learned_from is the speaker who said it."""


def authorized_memory(req: ChatRequest) -> Memory:
    """Group prompts withhold private entries (SPEC 6.3)."""
    if not req.is_group:
        return req.memory
    return req.memory.model_copy(update={
        "facts": [e for e in req.memory.facts if e.share_scope == "shared"],
        "ongoing": [e for e in req.memory.ongoing if e.share_scope == "shared"],
        "experiences": [e for e in req.memory.experiences if e.share_scope == "shared"],
    })


def heard_messages(req: ChatRequest):
    return [m for m in req.recent_messages if req.speaker_id in m.audience]


def build_chat_messages(req: ChatRequest) -> list[dict]:
    others = [p for p in req.participants if p != req.speaker_id]
    p = req.profile
    memory = authorized_memory(req)
    system = "\n\n".join([
        CHARACTER_INSTRUCTIONS.format(name=p.name, others=", ".join(others)),
        f"Profile:\nPersonality: {p.personality}\nSpeaking style: {p.speaking_style}\n"
        f"Background: {p.background}\nCurrently: {p.current_situation}\n"
        f"Relationship with the player: {p.starting_relationship}",
        "What you remember:\n" + "\n".join(f"- {e.text}" for e in memory.entries()) if memory.entries()
        else "What you remember: nothing specific yet.",
        f"Scene: {req.scene_context or 'at home'}. Present: {', '.join(req.participants)}.",
    ])
    out = [{"role": "system", "content": system}]
    for m in heard_messages(req):
        role = "assistant" if m.speaker == req.speaker_id else "user"
        out.append({"role": role, "content": f"[{m.speaker} to {m.addressee}] {m.text}"})
    return out


def build_memory_messages(req: MemoryUpdateRequest) -> list[dict]:
    system = MEMORY_INSTRUCTIONS.format(
        character_id=req.character_id, revision=req.base_revision + 1,
        cursor=req.new_events[-1].event_id, cap=3000)
    user = json.dumps({
        "existing_memory": req.memory.model_dump(),
        "new_events": [e.model_dump() for e in req.new_events],
    }, ensure_ascii=False)
    return [{"role": "system", "content": system}, {"role": "user", "content": user}]


class MarkerFilter:
    """Buffers the start of a reply to strip an optional '@to:<id>' first line."""

    MAX_PROBE = 40

    def __init__(self, speaker_id: str, participants: list[str]):
        self.valid = {p for p in participants if p != speaker_id}
        self.addressee = "player"
        self._buf = ""
        self._resolved = False

    def feed(self, text: str) -> str:
        if self._resolved:
            return text
        self._buf += text
        stripped = self._buf.lstrip()
        if not stripped:
            return ""
        if not "@to:".startswith(stripped[:4]):
            return self._release(self._buf)
        if "\n" in stripped:
            line, rest = stripped.split("\n", 1)
            target = line[4:].strip().lower()
            if target in self.valid:
                self.addressee = target
            return self._release(rest.lstrip())
        if len(stripped) > self.MAX_PROBE:
            return self._release(self._buf)
        return ""

    def flush(self) -> str:
        if self._resolved:
            return ""
        stripped = self._buf.lstrip()
        if stripped.startswith("@to:"):
            # Marker with no newline: treat any trailing words as the reply.
            parts = stripped[4:].split(None, 1)
            if parts and parts[0].lower() in self.valid:
                self.addressee = parts[0].lower()
            return self._release(parts[1] if len(parts) > 1 else "")
        return self._release(self._buf)

    def _release(self, text: str) -> str:
        self._resolved = True
        self._buf = ""
        return text
