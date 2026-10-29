"""Request/response schemas for the Naevia backend (SPEC sections 5.2-5.4, 6.1)."""

from typing import Literal

from pydantic import BaseModel, Field

MEMORY_TEXT_CAP = 3000  # combined characters per character (SPEC 6.1)
ENTRY_TEXT_CAP = 400


class Message(BaseModel):
    event_id: str
    speaker: str
    addressee: str = "player"
    audience: list[str]
    text: str


class MemoryEntry(BaseModel):
    id: str
    text: str = Field(min_length=1, max_length=ENTRY_TEXT_CAP)
    source_event_ids: list[str] = Field(min_length=1)
    learned_from: str
    share_scope: Literal["private", "shared"]


class Memory(BaseModel):
    schema_version: Literal[1] = 1
    character_id: str
    revision: int = Field(ge=0)
    last_processed_event_id: str | None = None
    facts: list[MemoryEntry] = []
    ongoing: list[MemoryEntry] = []
    experiences: list[MemoryEntry] = []

    def entries(self) -> list[MemoryEntry]:
        return [*self.facts, *self.ongoing, *self.experiences]

    def text_length(self) -> int:
        return sum(len(e.text) for e in self.entries())


class Profile(BaseModel):
    id: str
    name: str
    personality: str
    speaking_style: str
    background: str
    current_situation: str
    starting_relationship: str


class ChatRequest(BaseModel):
    request_id: str
    conversation_id: str
    speaker_id: str
    participants: list[str]
    profile: Profile
    memory: Memory
    recent_messages: list[Message] = Field(default=[], max_length=12)
    scene_context: str = ""

    @property
    def is_group(self) -> bool:
        return len([p for p in self.participants if p != "player"]) > 1


class MemoryUpdateRequest(BaseModel):
    request_id: str
    character_id: str
    base_revision: int = Field(ge=0)
    memory: Memory
    new_events: list[Message] = Field(min_length=1)


class MemoryUpdateResponse(BaseModel):
    request_id: str
    character_id: str
    base_revision: int
    memory: Memory


class Health(BaseModel):
    status: Literal["ok"] = "ok"
    mode: Literal["mock", "live"]
