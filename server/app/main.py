"""FastAPI entry point: /health, /v1/chat (NDJSON stream), /v1/memory/update (SPEC 5.2-5.4).

The service is stateless and never reads or writes game saves. Dialogue and
memory content are not logged.
"""

import json
from collections.abc import AsyncIterator

from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse

from .config import Settings
from .memory import MemoryValidationError, validate_proposal
from .prompts import MarkerFilter
from .provider import ProviderAdapter, ProviderError, make_provider
from .schemas import ChatRequest, Health, MemoryUpdateRequest, MemoryUpdateResponse


def create_app(settings: Settings | None = None, provider: ProviderAdapter | None = None) -> FastAPI:
    settings = settings or Settings.from_env()
    provider = provider or make_provider(settings)
    app = FastAPI(title="Naevia backend")

    def event(obj: dict) -> bytes:
        return (json.dumps(obj, ensure_ascii=False) + "\n").encode("utf-8")

    @app.get("/health", response_model=Health)
    async def health() -> Health:
        return Health(mode=settings.mode)

    @app.post("/v1/chat")
    async def chat(req: ChatRequest) -> StreamingResponse:
        if req.speaker_id not in req.participants:
            raise HTTPException(422, "speaker_id must be a participant")
        if req.memory.character_id != req.speaker_id:
            raise HTTPException(422, "memory does not belong to the speaker")

        async def stream() -> AsyncIterator[bytes]:
            marker = MarkerFilter(req.speaker_id, req.participants)
            try:
                async for delta in provider.stream_reply(req):
                    text = marker.feed(delta)
                    if text:
                        yield event({"type": "text_delta", "request_id": req.request_id, "text": text})
                tail = marker.flush()
                if tail:
                    yield event({"type": "text_delta", "request_id": req.request_id, "text": tail})
                yield event({"type": "done", "request_id": req.request_id,
                             "speaker_id": req.speaker_id, "addressee": marker.addressee})
            except ProviderError as exc:
                yield event({"type": "error", "request_id": req.request_id, "message": str(exc)})
            except Exception:
                yield event({"type": "error", "request_id": req.request_id,
                             "message": "The reply failed unexpectedly. Please retry."})

        return StreamingResponse(stream(), media_type="application/x-ndjson")

    @app.post("/v1/memory/update", response_model=MemoryUpdateResponse)
    async def memory_update(req: MemoryUpdateRequest) -> MemoryUpdateResponse:
        try:
            proposed = await provider.update_memory(req)
            memory = validate_proposal(req, proposed)
        except MemoryValidationError as exc:
            raise HTTPException(422, f"Rejected memory proposal: {exc}") from exc
        except ProviderError as exc:
            raise HTTPException(502, str(exc)) from exc
        return MemoryUpdateResponse(request_id=req.request_id, character_id=req.character_id,
                                    base_revision=req.base_revision, memory=memory)

    return app


app = create_app()
