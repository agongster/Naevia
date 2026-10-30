"""Model adapters: deterministic mock and OpenAI-compatible chat-completions (SPEC 5.1)."""

import asyncio
import json
from collections.abc import AsyncIterator

import httpx

from .config import Settings
from .prompts import authorized_memory, build_chat_messages, build_memory_messages, heard_messages
from .schemas import MEMORY_TEXT_CAP, ChatRequest, Memory, MemoryEntry, MemoryUpdateRequest


class ProviderError(RuntimeError):
    """Displayable failure talking to the model provider."""


class ProviderAdapter:
    async def stream_reply(self, req: ChatRequest) -> AsyncIterator[str]:
        raise NotImplementedError
        yield ""

    async def update_memory(self, req: MemoryUpdateRequest) -> Memory:
        raise NotImplementedError


class MockProvider(ProviderAdapter):
    """Deterministic replies and memory snapshots; no network (SPEC 5.3)."""

    chunk_delay = 0.03

    def reply_text(self, req: ChatRequest) -> str:
        heard = heard_messages(req)
        last = heard[-1] if heard else None
        situation = req.profile.current_situation.rstrip(".")
        others = [p for p in req.participants if p not in ("player", req.speaker_id)]
        if req.is_group and last and last.speaker == "player" and others:
            return (f"@to:{others[0]}\n"
                    f"[mock] {req.profile.name} heard: \"{last.text[:60]}\". "
                    f"What do you make of that, {others[0]}?")
        if last and last.speaker != "player" and last.speaker != req.speaker_id:
            return f"[mock] {req.profile.name} answers {last.speaker}: fair point. I'm {situation.lower()} myself."
        if last:
            recalled = self.recall(req)
            return (f"[mock] {req.profile.name} heard: \"{last.text[:60]}\". "
                    + (f"I remember: \"{recalled[:80]}\". " if recalled else "")
                    + f"Meanwhile I'm {situation.lower()}. Long replies are split at sentence boundaries.")
        return f"[mock] Hello from {req.profile.name}."

    @staticmethod
    def recall(req: ChatRequest) -> str | None:
        """Oldest authorized memory entry, so mock replies show memory working."""
        entries = authorized_memory(req).entries()
        return entries[0].text if entries else None

    async def stream_reply(self, req: ChatRequest) -> AsyncIterator[str]:
        for word in self.reply_text(req).split(" "):
            yield word + " "
            await asyncio.sleep(self.chunk_delay)

    async def update_memory(self, req: MemoryUpdateRequest) -> Memory:
        new_entries = []
        for i, ev in enumerate(req.new_events):
            if ev.speaker == req.character_id:
                continue
            scope = "private" if set(ev.audience) <= {"player", req.character_id} else "shared"
            new_entries.append(MemoryEntry(
                id=f"m{req.base_revision + 1}_{i}",
                text=f"{ev.speaker} said: {ev.text[:150]}",
                source_event_ids=[ev.event_id],
                learned_from=ev.speaker,
                share_scope=scope,
            ))
        experiences = [*req.memory.experiences, *new_entries]
        proposal = req.memory.model_copy(update={
            "revision": req.base_revision + 1,
            "last_processed_event_id": req.new_events[-1].event_id,
            "experiences": experiences,
        })
        while proposal.text_length() > MEMORY_TEXT_CAP and proposal.experiences:
            proposal.experiences.pop(0)  # consolidate by dropping the oldest exchange
        return proposal


class LiveProvider(ProviderAdapter):
    """OpenAI-compatible chat completions over HTTPX.

    NAEVIA_PROVIDER_BASE_URL must include the version prefix (e.g. .../v1);
    the adapter only appends /chat/completions.
    """

    def __init__(self, settings: Settings, transport: httpx.AsyncBaseTransport | None = None):
        self.transport = transport  # injectable for tests
        self.url = settings.base_url.rstrip("/") + "/chat/completions"
        self.model = settings.model
        self.headers = {"Authorization": f"Bearer {settings.api_key}"}
        self.timeout = httpx.Timeout(60.0, connect=10.0)

    async def stream_reply(self, req: ChatRequest) -> AsyncIterator[str]:
        body = {"model": self.model, "messages": build_chat_messages(req), "stream": True}
        try:
            async with httpx.AsyncClient(timeout=self.timeout, transport=self.transport) as client:
                async with client.stream("POST", self.url, json=body, headers=self.headers) as resp:
                    if resp.status_code != 200:
                        await resp.aread()
                        raise ProviderError(f"Provider returned HTTP {resp.status_code}")
                    async for line in resp.aiter_lines():
                        if not line.startswith("data:"):
                            continue
                        data = line[5:].strip()
                        if data == "[DONE]":
                            break
                        choices = json.loads(data).get("choices") or [{}]
                        delta = choices[0].get("delta", {}).get("content")
                        if delta:
                            yield delta
        except httpx.HTTPError as exc:
            raise ProviderError(f"Could not reach the model provider ({type(exc).__name__})") from exc

    async def update_memory(self, req: MemoryUpdateRequest) -> Memory:
        body = {"model": self.model, "messages": build_memory_messages(req),
                "response_format": {"type": "json_object"}}
        try:
            async with httpx.AsyncClient(timeout=self.timeout, transport=self.transport) as client:
                resp = await client.post(self.url, json=body, headers=self.headers)
        except httpx.HTTPError as exc:
            raise ProviderError(f"Could not reach the model provider ({type(exc).__name__})") from exc
        if resp.status_code != 200:
            raise ProviderError(f"Provider returned HTTP {resp.status_code}")
        content = resp.json()["choices"][0]["message"]["content"].strip()
        if content.startswith("```"):
            content = content.strip("`").removeprefix("json").strip()
        try:
            return Memory.model_validate_json(content)
        except ValueError as exc:
            raise ProviderError("Model returned an invalid memory snapshot") from exc


def make_provider(settings: Settings) -> ProviderAdapter:
    return LiveProvider(settings) if settings.mode == "live" else MockProvider()
