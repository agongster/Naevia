"""Prompt composition and recipient-marker handling (SPEC 4.3, 5.2, 5.3, 6.3)."""

import json
import re

from .schemas import ChatRequest, Memory, MemoryUpdateRequest

CHARACTER_INSTRUCTIONS = """You are {name}, a character in Naevia, a small cozy pixel world.
Stay in character. Reply in one to three short sentences, as spoken dialogue only.
Respond to what was actually said. You may mention your own current life.
When something you remember is relevant, use it naturally, the way a friend would
follow up on news (for example, a date or a worry the player mentioned before).
Do not flatter or praise by reflex, do not invent shared past events, and never
pressure the player to keep talking or guilt them for being away."""

PRIVATE_ADDRESSING = "Reply with your spoken words only, with no name, prefix, or marker."

# Seen live: without a clear format, models wrote "@to:player Hi" in private chats and
# "...\n\n@to:player Hi" in groups. MarkerFilter tolerates both, but ask clearly.
GROUP_ADDRESSING = """This is a group conversation with the player and {others}. You may answer the
player, or speak directly to {others} (ask them something, react to what they said).
When you speak to {others}, your first line must be exactly @to:{ids} and your
words follow on the next line. When you speak to the player, just reply with no marker.
Only if you truly have nothing to add, reply with exactly ... and nothing else."""

MEMORY_INSTRUCTIONS = """You maintain the memory notes of {character_id}.
Return ONLY a JSON object: the full replacement memory with keys schema_version (1),
character_id, revision ({revision}), last_processed_event_id ("{cursor}"),
facts, ongoing, experiences. Each entry: id, text, source_event_ids, learned_from,
share_scope ("private" or "shared").
- facts: stable things about people (the player studies statistics). ongoing: current
  situations and plans (an exam on Thursday); update or remove them when they change.
  experiences: brief summaries of meaningful exchanges.
- Write each entry as a short third-person note in your own words, e.g. "The player has
  a statistics exam on Thursday and is nervous." Keep news, plans and announcements,
  including ones made to a group; skip greetings and small talk. Never record words
  that were not said.
- Keep valid existing entries, merge duplicates, stay under {cap} characters of entry text.
- Cite only event ids from the existing memory or the new events. Never invent events.
- share_scope is "private" if any cited event's audience is only the player and
  {character_id}; "shared" only if every cited event was heard by a whole group.
- learned_from is the speaker who said it."""


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
    characters = [o for o in others if o != "player"]
    addressing = (GROUP_ADDRESSING.format(others=" and ".join(characters), ids="|".join(characters))
                  if req.is_group else PRIVATE_ADDRESSING)
    system = "\n\n".join([
        CHARACTER_INSTRUCTIONS.format(name=p.name),
        addressing,
        f"Profile:\nPersonality: {p.personality}\nSpeaking style: {p.speaking_style}\n"
        f"Background: {p.background}\nCurrently: {p.current_situation}\n"
        f"Relationship with the player: {p.starting_relationship}",
        "What you remember:\n" + "\n".join(f"- {e.text} ({_source(e.learned_from)})" for e in memory.entries())
        if memory.entries()
        else "What you remember: nothing specific yet.",
        f"Scene: {req.scene_context or 'at home'}. Present: {', '.join(req.participants)}.",
    ])
    out = [{"role": "system", "content": system}]
    for m in heard_messages(req):
        # The speaker's own lines stay unlabeled: with "[witch to player]" labels on
        # them, a live model started its reply with the same label.
        if m.speaker == req.speaker_id:
            out.append({"role": "assistant", "content": m.text})
        elif req.is_group:
            out.append({"role": "user", "content": f"{m.speaker} (to {m.addressee}): {m.text}"})
        else:
            out.append({"role": "user", "content": m.text})
    return out


def _source(learned_from: str) -> str:
    return "the player told you" if learned_from == "player" else f"you heard it from {learned_from}"


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
    """Buffers the start of a reply to strip an optional '@to:<id>' marker.

    Accepts the marker on its own first line or followed by a space on the same
    line, drops a lone ellipsis line when a real reply follows it, and drops a
    copied "[witch to player]" history label; all were seen from a live model. A reply that is only an ellipsis passes through, since
    that is the "nothing to add" signal.
    """

    MAX_PROBE = 40
    MARKER = re.compile(r"@to:\s?([A-Za-z_-]+)(\s)")
    LABEL = re.compile(r"\[[A-Za-z_-]+ to [A-Za-z_-]+\]\s*")  # copied history label, seen live

    def __init__(self, speaker_id: str, participants: list[str]):
        self.valid = {p for p in participants if p != speaker_id}
        self.addressee = "player"
        self._buf = ""
        self._resolved = False

    def feed(self, text: str) -> str:
        if self._resolved:
            return text
        self._buf += text
        return self._resolve(final=False)

    def flush(self) -> str:
        if self._resolved:
            return ""
        return self._resolve(final=True)

    def _resolve(self, final: bool) -> str:
        while True:
            stripped = self._buf.lstrip()
            if not stripped:
                return self._release("") if final else ""
            if stripped.startswith("["):
                label = self.LABEL.match(stripped)
                if label:
                    self._buf = stripped[label.end():]
                    continue
                if "]" not in stripped and len(stripped) <= self.MAX_PROBE and not final:
                    return ""
                return self._release(self._buf)
            if stripped.startswith(("...", "…")):
                rest = stripped.lstrip(".…")
                if not rest.strip():
                    return self._release(stripped.strip()) if final else ""
                if "\n" in rest[:len(rest) - len(rest.lstrip())]:
                    self._buf = rest  # drop the ellipsis line, then look for a marker
                    continue
                return self._release(self._buf)
            if not "@to:".startswith(stripped[:4]):
                return self._release(self._buf)
            match = self.MARKER.match(stripped)
            if match:
                self._set_target(match.group(1))
                return self._release(stripped[match.end():].lstrip())
            if final:
                parts = stripped[4:].split(None, 1) if stripped.startswith("@to:") else []
                if parts:
                    self._set_target(parts[0])
                    return self._release(parts[1] if len(parts) > 1 else "")
                return self._release(self._buf)
            if len(stripped) > self.MAX_PROBE:
                return self._release(self._buf)
            return ""

    def _set_target(self, target: str) -> None:
        if target.lower() in self.valid:
            self.addressee = target.lower()

    def _release(self, text: str) -> str:
        self._resolved = True
        self._buf = ""
        return text
