# Naevia — Demo 1

**Original design and foundation by Ryan Zhou ([@RyanZhou123232](https://github.com/RyanZhou123232)).** Ryan designed the game, wrote [SPEC.md](SPEC.md), and produced and validated the full pixel-art package under [art/](art/). Phase 2 work (backend, client, and these docs) by April Gong.

Naevia is a cozy 2D pixel game. You mine stone, furnish a small house, and talk with two AI characters, a witch and a blacksmith. Each one keeps their own memory, which persists between sessions. Replies appear in speech bubbles in the world, not in a chat sidebar. The full design is in [SPEC.md](SPEC.md), which is kept exactly as Ryan wrote it except for a clearly marked proposals section at the bottom.

## Current state at a glance

| Part | State |
|---|---|
| Art package (35 PNGs + manifest) | Delivered by Ryan; re-checked 2026-10-29: all 35 match manifest sizes, all RGBA |
| Backend (`server/`) | Implemented; mock mode works end to end; 33 pytest tests pass; live mode is tested against a fake provider only, not a real one |
| Godot client (`client/`) | **Playable demo (milestone A) on Godot 4.7.2, macOS.** Movement, jumping, mining, furniture buy/place/move/store, pigeon and blacksmith visits, click-to-talk with streamed replies in bubbles, history, saves. The automated smoke test passes (43 checks) |
| Memory (milestone C), group chat (milestone D) | Not started. Characters get an empty memory with every message |
| Windows build (`build/windows/`) | Not started; no export preset yet |
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

### Game client

Requires Godot 4.7.x (tested with 4.7.2 stable). Start the backend first. The game still runs without it, but chat will show a "can't reach the backend" bubble with a Retry button.

```bash
godot --path client                         # or open client/project.godot in the editor and press Play
```

Controls:
- **A / D** walk, **Space** jump.
- **Hold left mouse** on stone within about 4 tiles to mine it (1 s per tile, 1 stone each).
- **Bag** (top left): buy a table, chair or lamp for 3 stone. Left click places it, right click cancels.
- **Arrange** (in the Bag): click placed furniture to pick it up, then click to drop it or press **Store**. Stored pieces are placed again for free.
- **Contacts** (top right): call the witch's pigeon or the blacksmith. They also show up on their own after about 45 s and 100 s. Click either one to talk, type in the field, and click **Send**.
- **History** shows past dialogue. **Dev** has instant contacts, Reset resources, +9 stone, and Wipe save.

Launch options go after `--`:
- `--save-slot=<name>` uses `user://saves/<name>/` instead of `default`, for fresh-save testing without touching the real save.
- `--backend-url=http://127.0.0.1:8010` points at a backend on another port. This was needed on the dev Mac, because another app already uses 8000.

On macOS, saves are in `~/Library/Application Support/Godot/app_userdata/Naevia/saves/<slot>/`. On Windows they are in `%APPDATA%\Godot\app_userdata\Naevia\saves\<slot>\`.

If you change anything in `art/export/`, run `python3 client/tools/sync_art.py` from the repo root. It recopies the PNGs and regenerates `client/data/visuals.json`.

### Tests

```bash
cd server && .venv/bin/python -m pytest -q                       # backend: 33 tests

# client smoke test: needs a display (not --headless) and a mock backend running
godot --path client --fixed-fps 60 res://tests/smoke_test.tscn -- \
      --save-slot=smoke --shots=/tmp/naevia-shots --backend-url=http://127.0.0.1:8000
```

The smoke test opens a small always-on-top window for about 10 seconds. It plays through movement, mining, furniture, both contacts, a backend failure and retry, and a reload from disk, using simulated mouse and keyboard input. It saves screenshots to `--shots` and prints `SMOKE PASS` or `SMOKE FAIL`. `--fixed-fps 60` makes timing deterministic, because macOS throttles windows hidden behind other apps. The test refuses to run on the `default` save slot.

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
client/
  project.godot          640x360 viewport, 1280x720 window, integer scale, nearest filtering, Compatibility renderer
  assets/                Copies of art/export PNGs (generated by tools/sync_art.py; do not hand-edit)
  tools/sync_art.py      Copies art/export into assets/ and builds data/visuals.json from Ryan's manifest
  data/
    visuals.json         Visual ID -> res:// path, frame layout, fps, anchor (generated)
    items.json, tiles.json, furniture.json   Gameplay definitions: solidity, mineable, drops, cost, footprint
    level.json           The level as ordered rectangle fills + props (edit this to change the map)
    characters/*.json    Witch and blacksmith profiles (SPEC 4.3 starter defaults); edit freely
    config.json          Backend URL, contact timers, save debounce
    bubble_style.tres    All bubble sizes/colors in one resource (SPEC 4.2)
  scenes/
    World.tscn           Main scene: Sky, Landscape (Parallax2D), Walls/Terrain/Resources TileMapLayers,
                         Props, Furniture, Characters, Player, the controllers, and UI
    Player.tscn          CharacterBody2D, 20x42 collider, AnimatedSprite2D, Camera2D
    Npc.tscn             Base for Witch.tscn / Blacksmith.tscn (Area2D click target on layer 2)
    Pigeon.tscn, UI.tscn
  scripts/
    defs.gd, visuals.gd, save_manager.gd, api_client.gd     Autoloads (data, visual lookup, saves, HTTP)
    world.gd             Builds the TileSet and level, answers tile queries, tracks the pointer
    player_controller.gd, mining_controller.gd, furniture_controller.gd
    conversation_coordinator.gd   Conversation/request IDs, history commits, retry
    bubble_controller.gd, bubble_style.gd, hud.gd          Speech bubbles and HUD, built from native controls
    npc.gd, pigeon.gd, contact_scheduler.gd                Visitors and the one-at-a-time invitation timers
  tests/smoke_test.gd    End-to-end playthrough with simulated input and screenshots
```

How the client is put together:

- **Art loads at runtime.** `SpriteFrames` and the `TileSet` are built from `visuals.json` and `tiles.json` when the game starts, so the `.tscn` files contain only node structure. Changing an asset means changing a data file, not a scene.
- **World waits for itself before wiring the UI.** Godot runs children's `_ready` before the parent's, so World calls `contacts.setup()` and `ui.setup()` explicitly once its own references exist.
- **Mouse input comes from events.** The pointer is read from mouse events in `World._input`, not from `get_global_mouse_position()`, so simulated input in the smoke test behaves exactly like a real mouse.
- **UI clicks never reach the world.** Mining and placement react only to `_unhandled_input`, so a click on the UI never mines or places anything behind it.

Design decisions worth knowing:

- **Mock replies start with `[mock]`.** That way nobody mistakes a mock reply for a live one during acceptance.
- **In mock mode, group chat always passes the turn.** When the player speaks in a group, the mock's first responder addresses the other character with `@to:`. That exercises the routing between characters without a live model.
- **Memory is checked on both sides.** The backend checks every memory proposal (including the live model's) before returning it. Per SPEC §5.4, the client must still recheck character and revision before it replaces a file.
- **The backend never logs dialogue or memory, and never touches save files.**

## Acceptance criteria report

Every check ID comes from SPEC §10/§12.2. Status as of 2026-10-29, commit `8467900`.

**What "mock smoke test" means below:** this was observed in the real Godot client on macOS (Godot 4.7.2, Apple M2), with the backend in mock mode. The evidence is the automated `client/tests/smoke_test.gd` plus its screenshots. SPEC §10 only accepts a play session in the **Windows build with a live model**, so these items stay NOT RUN until that happens.

| ID | Requirement (short) | Status | Evidence so far / remaining work |
|---|---|---|---|
| 10.1-1 | Open Windows build, enter home + mining area | NOT RUN | Works on macOS from the editor/CLI. No Windows export preset or build yet |
| 10.1-2 | Coherent tile/character proportions | NOT RUN | 16 px tiles and a 20×42 player collider; the scene is assembled from Ryan's art and matches his `scene_direction.png` layout. Needs an owner's visual sign-off |
| 10.1-3 | Move, jump, animated walk + mining | NOT RUN | Mock smoke test: walk animation plays while moving, the mine animation plays while holding, crack frames advance with progress, stone chips burst when a tile breaks |
| 10.1-4 | Mine, buy 3 furniture types, place/move/store | NOT RUN | Mock smoke test: 3 stone mined → table bought and placed; chair and lamp placed; table moved; chair stored and placed again without paying |
| 10.2-1 | Pigeon arrives, blacksmith visits; click to talk | NOT RUN | Mock smoke test: both arrive (timer or Contacts/Dev), and clicking each opens the right conversation. Send is a button; Enter is optional |
| 10.2-2 | Replies in attached bubbles, no sidebar | NOT RUN | Bubbles anchor above the pigeon or blacksmith and have a tail. There is no sidebar |
| 10.2-3 | Compact/wrapping/segmented bubbles on screen | NOT RUN | Short text shrinks the bubble, long text wraps and splits at sentence boundaries ("click for more 1/3"), and bubbles are clamped on screen. Chinese text has **not** been checked: no CJK font is bundled yet |
| 10.2-4 | Click field, type, Send; no movement/mining leak | NOT RUN | Mock smoke test: pressing D while the field is focused types into it and doesn't move the player; clicking Bag buttons doesn't place furniture behind them |
| 10.2-5 | Play while waiting; history viewable | NOT RUN | Mock smoke test: the player walks while a reply streams. The History panel lists each character's exchanges |
| 10.3-1 | Both characters answer unscripted via live API | BLOCKED | No provider/key. Live adapter only tested against a fake provider |
| 10.3-2 | Distinct voices, own lives | NOT RUN | Profiles written in `client/data/characters/` (starter defaults from SPEC §4.3). Needs a live model to judge |
| 10.3-3 | Brief, non-generic replies | NOT RUN | Instructions ask for 1–3 sentences and no reflexive praise |
| 10.3-4 | No guilt/penalty for ignoring | NOT RUN | An ignored visitor leaves after 60 s without saying anything, and no relationship stat exists. Live wording still unchecked |
| 10.4-1 | Witch uses a told detail later | NOT RUN | **Client memory (milestone C) not built**: the client sends an empty memory |
| 10.4-2 | Recall survives restart | NOT RUN | Milestone C |
| 10.4-3 | Blacksmith not given witch's private memory | NOT RUN | Backend filters by audience (tested). Separate history files per character. Memory files not built yet |
| 10.4-4 | Exam-finished update reflected | NOT RUN | Milestone C + live model |
| 10.5-1 | Invite Both; shared announcement | NOT RUN | **Milestone D not built**; the Invite Both button is disabled and says so |
| 10.5-2 | Characters address each other, correct bubbles | NOT RUN | Backend `@to:` routing tested; client group turns not built |
| 10.5-3 | Learns shareable detail from other character | NOT RUN | Milestones C + D |
| 10.5-4 | Group doesn't expose private memory; ends turns | NOT RUN | Backend withholds private entries in group prompts (tested). Client 3-turn cap not built |
| 10.6-1 | Everything persists across restart | NOT RUN | Mock smoke test: stone, furniture, mined cells and player position all survive a rebuild from disk, and history is saved as JSONL. Memories are not built yet |
| 10.6-2 | Responsive during replies + memory work | NOT RUN | Streaming is polled without blocking, and the player moved during a reply. There's no memory work yet to test |
| 10.6-3 | Clear failure state, retry, no duplicates | NOT RUN | Mock smoke test: with the backend unreachable, a bubble says "Can't reach the local backend… Is it running?" and offers Retry. Retry completed the exchange with exactly 2 history events (no duplicate player message) |
| 10.7-1 | Another dev can follow setup to run everything | NOT RUN | Backend and client steps verified on macOS. Windows and export steps don't exist yet |
| 10.7-2 | Config examples, pinned deps, no secrets | NOT RUN | `.env.example`, `requirements.lock` and Dev contact triggers exist; `.env` is gitignored. Known issues are listed below |

**Summary: 0 / 26 PASS.** 11 checks have supporting evidence from the mock smoke test on macOS. Memory (C), group chat (D), a live model, and the Windows build (E) are all still needed before any check can pass.

### Known issues and placeholders

- **No CJK font is bundled.** Godot's default font plus system fallback renders English. Chinese has not been checked. SPEC §3.3 requires a bundled, redistributable English/Chinese font.
- **Character memory is an empty stub.** Every chat request sends an empty memory, until milestone C is built.
- **Invite Both is disabled** until milestone D. The witch's scene exists but is never shown yet.
- **Furniture placement is forgiving.** It drops onto the first solid floor under the cursor, anywhere in the world, not just inside the house.
- **The player's own messages don't appear as a bubble.** They show only in History.
- **Mined tiles stay gone.** Only the Dev "Reset resources" button restores them.

## Next steps for whoever picks this up

1. **Milestone C (memory):** add a `MemoryStore` that keeps `characters/<id>.memory.json`, sends the speaker's memory with each request, and calls `/v1/memory/update` in the background after each completed turn. Validate the proposal and replace the file atomically (SPEC 6.2). The backend side is done.
2. **Milestone D (group):** Invite Both brings the witch and blacksmith into the house, alternates or targets turns, honors `@to:` addressees, caps character turns at 3 per player message, and writes `history/group.jsonl`.
3. Choose a provider and model, then run one live smoke test (SPEC §11.2).
4. Bundle an English/Chinese font with a license that allows redistribution. Ryan's package doesn't include one, by design.
5. Add the `Windows Desktop` export preset, export from macOS, and run the two acceptance sessions in SPEC §10 on a Windows PC.

See [HANDOFF_REPORT.md](HANDOFF_REPORT.md) for an assessment of the inherited work, and [prompt_log.md](prompt_log.md) for the AI-assisted development log.
