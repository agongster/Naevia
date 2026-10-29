# Naevia — Demo 1

**Original design and foundation by Ryan Zhou ([@RyanZhou123232](https://github.com/RyanZhou123232)).** Ryan designed the game, wrote [SPEC.md](SPEC.md), and produced and validated the full pixel-art package under [art/](art/). Phase 2 work (backend, client, and these docs) by April Gong.

Naevia is a cozy 2D pixel game. You mine stone, furnish a small house, and talk with two AI characters, a witch and a blacksmith. Each one keeps their own memory, which persists between sessions. Replies appear in speech bubbles in the world, not in a chat sidebar. The full design is in [SPEC.md](SPEC.md), which is kept exactly as Ryan wrote it except for a clearly marked proposals section at the bottom.

## Current state at a glance

| Part | State |
|---|---|
| Art package (35 PNGs + manifest) | Delivered by Ryan; re-checked 2026-10-29: all 35 match manifest sizes, all RGBA |
| Backend (`server/`) | Implemented; mock mode works end to end; 33 pytest tests pass; live mode is tested against a fake provider only, not a real one |
| Godot client (`client/`) | **Not started.** Godot is not installed on the current dev machine |
| Windows build (`build/windows/`) | Not started |
| Live AI acceptance | Not run; no provider/model chosen yet |

## Running it

### Backend (macOS / Linux)

Requires Python 3.12.

```bash
cd server
python3.12 -m venv .venv
.venv/bin/python -m pip install -r requirements.lock
cp -n .env.example .env          # -n: never overwrite an existing configured .env
.venv/bin/python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --env-file .env
```

Then open `http://127.0.0.1:8000/health`. It should return `{"status":"ok","mode":"mock"}`.

### Backend (Windows PowerShell)

These are the commands from SPEC §11.1. They have not been run on Windows yet.

```powershell
Set-Location server
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.lock
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --env-file .env
```

### Tests

```bash
cd server && .venv/bin/python -m pytest -q
```

### Live AI

In `server/.env`, set `NAEVIA_MODEL_MODE=live` and fill in the three `NAEVIA_PROVIDER_*` / `NAEVIA_MODEL` values. **The base URL includes the version prefix** (for example `https://api.openai.com/v1`); the adapter appends `/chat/completions`. Restart uvicorn. The server refuses to start in live mode if any of the three values is missing. Never commit `.env`.

### Trying the chat endpoint by hand

```bash
curl -N -X POST http://127.0.0.1:8000/v1/chat -H 'content-type: application/json' -d '{
 "request_id":"r1","conversation_id":"c1","speaker_id":"witch","participants":["player","witch"],
 "profile":{"id":"witch","name":"Witch","personality":"dry","speaking_style":"brief","background":"herbalist",
            "current_situation":"Tending an unusual garden","starting_relationship":"acquaintance"},
 "memory":{"schema_version":1,"character_id":"witch","revision":0,"facts":[],"ongoing":[],"experiences":[]},
 "recent_messages":[{"event_id":"e1","speaker":"player","audience":["player","witch"],"text":"Exams next week."}]}'
```

The response is one JSON event per line: several `text_delta` events, then one `done` event. If something fails, the stream ends with an `error` event instead.

## Code map

```text
SPEC.md                  Ryan's design spec (unchanged) + proposed additions at the bottom
art/                     Ryan's art package: export/ (runtime PNGs + manifest.json), previews/, references/, source/
server/
  app/main.py            FastAPI app: GET /health, POST /v1/chat (NDJSON stream), POST /v1/memory/update
  app/schemas.py         Pydantic models: Message, Memory/MemoryEntry, Profile, ChatRequest, MemoryUpdate*
  app/config.py          Reads NAEVIA_* env vars; refuses to start in live mode without all three provider values
  app/prompts.py         Prompt order (instructions → profile → memory → scene → dialogue); hides private
                         memory in group chats; only includes messages the speaker actually heard;
                         MarkerFilter strips a leading "@to:<id>" line even when it is split across chunks
  app/provider.py        ProviderAdapter; MockProvider (deterministic, offline); LiveProvider (OpenAI-compatible
                         SSE via HTTPX, injectable transport for tests)
  app/memory.py          validate_proposal: character id, revision = base+1, cited sources must exist,
                         every event must have been heard, cursor = last event, 3,000-char cap
  tests/                 33 tests; test_live_adapter.py fakes the provider with httpx.MockTransport
  .env.example           Safe defaults (mock mode). Copy to .env
  requirements.lock      Full pip freeze from Python 3.12.9
client/                  (to create) Godot 4.7 project; see SPEC §3 for the required scenes and scripts
```

Design decisions worth knowing:

- **Mock replies start with `[mock]`.** That way nobody mistakes a mock reply for a live one during acceptance.
- **In mock mode, group chat always passes the turn.** When the player speaks in a group, the mock's first responder addresses the other character with `@to:`. That exercises the routing between characters without a live model.
- **Memory is checked on both sides.** The backend checks every memory proposal (including the live model's) before returning it. Per SPEC §5.4, the client must still recheck character and revision before it replaces a file.
- **The backend never logs dialogue or memory, and never touches save files.**

## Acceptance criteria report

Every check ID comes from SPEC §10/§12.2. Status as of 2026-10-29, commit `e5ccfc2`. Nothing below was observed in a running game, because no game exists yet.

| ID | Requirement (short) | Status | Notes / remaining work |
|---|---|---|---|
| 10.1-1 | Open Windows build, enter home + mining area | NOT RUN | No client yet |
| 10.1-2 | Coherent tile/character proportions | NOT RUN | Art meets the size contract; nothing integrated yet |
| 10.1-3 | Move, jump, animated walk + mining | NOT RUN | Walk/mine sheets exist (4 frames each) |
| 10.1-4 | Mine, buy 3 furniture types, place/move/store | NOT RUN | |
| 10.2-1 | Pigeon arrives, blacksmith visits; click to talk | NOT RUN | |
| 10.2-2 | Replies in attached bubbles, no sidebar | NOT RUN | |
| 10.2-3 | Compact/wrapping/segmented bubbles on screen | NOT RUN | |
| 10.2-4 | Click field, type, Send; no movement/mining leak | NOT RUN | |
| 10.2-5 | Play while waiting; history viewable | NOT RUN | Backend streams without blocking (async), but the client side is untested |
| 10.3-1 | Both characters answer unscripted via live API | BLOCKED | No provider/key. Live adapter only tested against a fake provider |
| 10.3-2 | Distinct voices, own lives | NOT RUN | Prompt includes profile and current situation; profiles not written yet |
| 10.3-3 | Brief, non-generic replies | NOT RUN | Instructions ask for 1–3 sentences and no reflexive praise |
| 10.3-4 | No guilt/penalty for ignoring | NOT RUN | Instructions forbid guilt-tripping; no relationship stat exists |
| 10.4-1 | Witch uses a told detail later | NOT RUN | Mock memory update records it; test `test_endpoint_mock_update_*` passes |
| 10.4-2 | Recall survives restart | NOT RUN | Needs client save files |
| 10.4-3 | Blacksmith not given witch's private memory | NOT RUN | Backend side: prompts include only messages the speaker heard (`test_prompt_only_includes_heard_messages`). The client must also send only the speaker's own file |
| 10.4-4 | Exam-finished update reflected | NOT RUN | Needs live memory model |
| 10.5-1 | Invite Both; shared announcement | NOT RUN | |
| 10.5-2 | Characters address each other, correct bubbles | NOT RUN | `@to:` routing tested (`test_group_marker_is_stripped_and_routed`) |
| 10.5-3 | Learns shareable detail from other character | NOT RUN | Mock marks group speech `shared` with `learned_from` = speaker (`test_group_events_become_shared`) |
| 10.5-4 | Group doesn't expose private memory; ends turns | NOT RUN | Private entries are left out of group prompts (`test_group_prompt_withholds_private_memory`). The 3-turn cap is client work |
| 10.6-1 | Everything persists across restart | NOT RUN | |
| 10.6-2 | Responsive during replies + memory work | NOT RUN | |
| 10.6-3 | Clear failure state, retry, no duplicates | NOT RUN | Backend sends an `error` event on HTTP failure or no connection (tested). Retry and dedupe are client work |
| 10.7-1 | Another dev can follow setup to run everything | NOT RUN | Backend steps verified on macOS only; client/export steps don't exist |
| 10.7-2 | Config examples, pinned deps, no secrets | NOT RUN | Partly done: `.env.example` and `requirements.lock` present; `.env` is gitignored. Contact triggers and placeholder list depend on the client |

**Summary: 0 / 26 PASS.** The backend contract behind ten checks is implemented and unit-tested, but per SPEC §10 nothing passes until it is played in the Windows build with a live model.

## Next steps for whoever picks this up

1. Install Godot 4.7 (check that this version exists; otherwise use the latest 4.x stable and record that). Create `client/` following SPEC §3.1 and milestone A in §8.
2. Choose a provider and model, then run one live smoke test (SPEC §11.2).
3. Write the character profiles in `client/data/characters/` (SPEC §4.3 starter defaults).
4. Bundle an English/Chinese font with a license that allows redistribution. Ryan's package doesn't include one, by design.
5. Export to Windows and run the two acceptance sessions in SPEC §10.

See [HANDOFF_REPORT.md](HANDOFF_REPORT.md) for an assessment of the inherited work, and [prompt_log.md](prompt_log.md) for the AI-assisted development log.
