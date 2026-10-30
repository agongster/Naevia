"""Validation of proposed memory snapshots (SPEC 5.4, 6.2).

The backend never writes saves; it only checks that a proposal is safe to hand
back. The Godot client repeats the character/revision checks before replacing
its file.
"""

from .schemas import MEMORY_TEXT_CAP, Memory, MemoryUpdateRequest


class MemoryValidationError(ValueError):
    pass


def validate_proposal(req: MemoryUpdateRequest, proposed: Memory) -> Memory:
    if req.memory.character_id != req.character_id:
        raise MemoryValidationError("request memory belongs to another character")
    if req.memory.revision != req.base_revision:
        raise MemoryValidationError("base_revision does not match supplied memory")
    if proposed.character_id != req.character_id:
        raise MemoryValidationError("proposal changes another character's memory")
    if proposed.revision != req.base_revision + 1:
        raise MemoryValidationError("proposal revision must be base_revision + 1")

    for ev in req.new_events:
        if req.character_id not in ev.audience:
            raise MemoryValidationError(f"event {ev.event_id} was not heard by {req.character_id}")

    allowed = {ev.event_id for ev in req.new_events}
    for entry in req.memory.entries():
        allowed.update(entry.source_event_ids)
    seen_ids = set()
    for entry in proposed.entries():
        if entry.id in seen_ids:
            raise MemoryValidationError(f"duplicate entry id {entry.id}")
        seen_ids.add(entry.id)
        invented = set(entry.source_event_ids) - allowed
        if invented:
            raise MemoryValidationError(f"entry {entry.id} cites unknown events {sorted(invented)}")

    if proposed.text_length() > MEMORY_TEXT_CAP:
        raise MemoryValidationError("memory exceeds text cap")
    if proposed.last_processed_event_id != req.new_events[-1].event_id:
        raise MemoryValidationError("processing cursor must equal the last supplied event")
    enforce_private_scope(req, proposed)
    return proposed


def enforce_private_scope(req: MemoryUpdateRequest, proposed: Memory) -> None:
    """An entry citing anything said privately stays private, whatever the model says.

    Seen live: gpt-4o-mini labeled a private exam conversation "shared", which put
    it into a group prompt. Downgrading (rather than rejecting) can only make memory
    more private and keeps updates from failing and retrying forever.
    """
    private = {ev.event_id for ev in req.new_events if set(ev.audience) <= {"player", req.character_id}}
    for entry in req.memory.entries():
        if entry.share_scope == "private":
            private.update(entry.source_event_ids)
    for entry in proposed.entries():
        if private.intersection(entry.source_event_ids):
            entry.share_scope = "private"
