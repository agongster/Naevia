# Naevia — Demo 1

**Original design and foundation by Ryan Zhou ([@RyanZhou123232](https://github.com/RyanZhou123232)).** Ryan designed the game, wrote [SPEC.md](SPEC.md), and produced and validated the full pixel-art package under [art/](art/). Phase 2 work (backend, client, and these docs) by April Gong.

Naevia is a cozy 2D pixel game. You mine stone, furnish a small house, and talk with two AI characters, a witch and a blacksmith. Each one keeps their own memory, which persists between sessions. Replies appear in speech bubbles in the world, not in a chat sidebar. The full design is in [SPEC.md](SPEC.md), which is kept exactly as Ryan wrote it except for a clearly marked proposals section at the bottom.

## Current state at a glance

| Part | State |
|---|---|
| Art package (35 PNGs + manifest) | Delivered by Ryan; re-checked 2026-10-29: all 35 match manifest sizes, all RGBA |
| Backend (`server/`) | Implemented; mock and live mode work end to end; 49 pytest tests pass; live mode verified with OpenAI `gpt-4o-mini` on 2026-10-30 |
| Godot client (`client/`) | **Playable demo (milestone A) on Godot 4.7.2, macOS.** Movement, jumping, mining, furniture buy/place/move/store, pigeon and blacksmith visits, click-to-talk with streamed replies in bubbles, history, saves, per-character memory (milestone C), and group chat (milestone D). The automated smoke test passes (97 checks) |
| Memory (milestone C) | **Built.** Each character has their own memory file, updated in the background after every exchange, checked by the client before it replaces the file, and kept across restarts. Verified in mock mode only |
| Group chat (milestone D) | **Built.** Invite Both brings both characters into the house; turn-taking, `@to:` handoffs, a 3-turn cap, a shared `group.jsonl` transcript, and listeners learning shared knowledge from each other. Verified in mock mode only |
| Windows build (`build/windows/`) | **Exported 2026-10-30** from macOS with Godot 4.7.2 official templates: `Naevia.exe` (game, data embedded) and `Naevia.console.exe` (same game with a console for error output). The export's data package was run on macOS and renders the full world, but the `.exe` itself **has not been run on Windows yet**. Not in git (110 MB); see below |
| Live AI | **Live smoke test run 2026-10-30** (SPEC §11.2) with OpenAI `gpt-4o-mini`, base URL `https://api.openai.com/v1`, on macOS. The in-game live check passes. Formal acceptance still needs the Windows build |

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

### Playing the Windows build

You need the exported build (`Naevia-windows-x86_64.zip`, see *Exporting for Windows* below) plus this repository for the backend. It's a two-process launch, as SPEC §11.4 allows:

1. Install Python 3.12 and start the backend with the PowerShell commands above. For live AI, fill in `server\.env` first; mock mode works without a key.
2. Unzip the build anywhere and double-click `Naevia.exe`. No Godot editor is needed. The build is unsigned, so Windows SmartScreen may warn: choose **More info → Run anyway**.
3. If something goes wrong, run `Naevia.console.exe` instead, from the same folder. It is the same game with a console window that shows error output.

The game connects to `http://127.0.0.1:8000`. To use another port, run `Naevia.exe -- --backend-url=http://127.0.0.1:8010`. Saves go to `%APPDATA%\Godot\app_userdata\Naevia\saves\default\`; add `-- --save-slot=test` to test with a fresh save. If the backend isn't running, the game still plays and conversations show a Retry button.

### Exporting for Windows

The checked-in preset `client/export_presets.cfg` is named `Windows Desktop`. It embeds the game data in the `.exe`, includes the `.json` data files (the game reads them directly, so the default export would leave them out), and excludes `tests/`. Steps used on 2026-10-30 (macOS, Godot 4.7.2):

1. Install the matching export templates. In the editor: **Editor → Manage Export Templates → Download and Install**. Or by hand: download `Godot_v4.7.2-stable_export_templates.tpz` from the Godot 4.7.2 GitHub release, check it against that release's `SHA512-SUMS.txt`, and unzip `templates/version.txt` and `templates/windows_*_x86_64*.exe` into `~/Library/Application Support/Godot/export_templates/4.7.2.stable/` (Windows: `%APPDATA%\Godot\export_templates\4.7.2.stable\`).
2. Export:
   ```bash
   mkdir -p build/windows
   godot --headless --path client --export-release "Windows Desktop" ../build/windows/Naevia.exe
   ```
   Output: `build/windows/Naevia.exe` (about 110 MB) and `build/windows/Naevia.console.exe`.
3. Zip both for sharing: `cd build/windows && zip -9 ../Naevia-windows-x86_64.zip Naevia.exe Naevia.console.exe` (about 38 MB).

`build/` is in `.gitignore`, because GitHub rejects files over 100 MB. Share the zip some other way, for example as a GitHub Release attachment. No API key is in the build; the key lives only in `server/.env`.

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
- **Contacts → Invite Both**: the witch and blacksmith walk in through the door and a group conversation opens. Name one of them ("Blacksmith, …") to have them answer first; otherwise they take turns going first. You can send again while they're talking; your message goes next. **Close** sends them home.
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

The smoke test opens a small always-on-top window for about 20 seconds. It plays through movement, mining, furniture, both contacts, a backend failure and retry, memory updates and isolation, a failed memory update, a reload from disk that checks memory recall, and a group conversation (turn order, handoffs, the 3-turn cap, privacy of request context, learning from each other), using simulated mouse and keyboard input. It also checks that the client rejects bad memory proposals. It saves screenshots to `--shots` and prints `SMOKE PASS` or `SMOKE FAIL`. `--fixed-fps 60` makes timing deterministic, because macOS throttles windows hidden behind other apps. The test refuses to run on the `default` save slot.

### Live AI

In `server/.env`, set `NAEVIA_MODEL_MODE=live` and fill in the three `NAEVIA_PROVIDER_*` / `NAEVIA_MODEL` values. **The base URL includes the version prefix** (for example `https://api.openai.com/v1`); the adapter appends `/chat/completions`. Restart uvicorn. The server refuses to start in live mode if any of the three values is missing. Never commit `.env`; it is in `.gitignore`.

Tested with `NAEVIA_PROVIDER_BASE_URL=https://api.openai.com/v1` and `NAEVIA_MODEL=gpt-4o-mini`. Two live checks exist, and each makes about 10–15 model calls:

```bash
# in the real game: private chats, streaming into bubbles, group chat, memory, request privacy
godot --path client --fixed-fps 60 res://tests/live_check.tscn -- \
      --save-slot=live --shots=/tmp/naevia-live --backend-url=http://127.0.0.1:8000
# backend only: prints replies, streaming timing, memory proposals, and three group trials
cd server && .venv/bin/python tools/live_check.py http://127.0.0.1:8000 ../client/data/characters
```

Live replies differ every run, so these assert structure (streaming, no markers, privacy, accepted memory) and print the replies for a person to judge. Results from 2026-10-30 are in the acceptance report below.

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
  tests/                 49 tests; test_live_adapter.py fakes the provider with httpx.MockTransport
  tools/live_check.py    Backend-only live check (prints replies, memory proposals, group trials)
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
    memory_store.gd      Autoload: per-character memory files, background /v1/memory/update calls,
                         client-side proposal checks, per-character queue, retry and restart recovery
    world.gd             Builds the TileSet and level, answers tile queries, tracks the pointer
    player_controller.gd, mining_controller.gd, furniture_controller.gd
    conversation_coordinator.gd   Private and group conversations: request IDs, turn order (named →
                                  alternate → @to: handoff, max 3 per message), queued player message,
                                  history commits, retry; waits for a character's memory update first
    bubble_controller.gd, bubble_style.gd, hud.gd          Speech bubbles and HUD, built from native controls
    npc.gd, pigeon.gd, contact_scheduler.gd                Visitors, one-at-a-time invitation timers, Invite Both
  tests/smoke_test.gd    End-to-end playthrough with simulated input and screenshots (mock backend)
  tests/live_check.gd    Same helpers against a live backend: structural checks, prints replies
```

How the client is put together:

- **Art loads at runtime.** `SpriteFrames` and the `TileSet` are built from `visuals.json` and `tiles.json` when the game starts, so the `.tscn` files contain only node structure. Changing an asset means changing a data file, not a scene.
- **World waits for itself before wiring the UI.** Godot runs children's `_ready` before the parent's, so World calls `contacts.setup()` and `ui.setup()` explicitly once its own references exist.
- **Mouse input comes from events.** The pointer is read from mouse events in `World._input`, not from `get_global_mouse_position()`, so simulated input in the smoke test behaves exactly like a real mouse.
- **UI clicks never reach the world.** Mining and placement react only to `_unhandled_input`, so a click on the UI never mines or places anything behind it.

Design decisions worth knowing:

- **Mock replies start with `[mock]`.** That way nobody mistakes a mock reply for a live one during acceptance.
- **In mock mode, group chat always passes the turn.** When the player speaks in a group, the mock's first responder addresses the other character with `@to:`, and the other answers the player. That exercises the routing between characters without a live model. A player message containing `#chain` makes mock characters keep handing the turn back and forth, which is how the smoke test checks the 3-turn cap. Live models ignore it.
- **Group privacy is enforced twice.** For group turns the client sends `MemoryStore.shareable(id)` (shared entries only), and the backend filters private entries again. `ApiClient.last_chat_requests` keeps the last request body per speaker in memory (never on disk), so you can inspect exactly what context a character got (SPEC 10.4-3).
- **Group turns.** A message to everyone gives each character a turn (they may decline with "..."); a named character answers alone unless they hand off. This rule came from the live test: with only nominated turns, a live model usually answered the player, so the second character never spoke.
- **Share scope is enforced by code.** A memory entry citing anything said privately is forced to `private` by both the backend and `MemoryStore`, whatever the model labeled it. In live testing the model labeled a private exam conversation "shared", which put it into a group prompt.
- **Group memory.** `MemoryStore.pending_events(id)` merges the character's private history with the group transcript in time order (event IDs start with a millisecond timestamp). Memory updates for both guests run when a player message's turns finish or the group closes, not between turns. A reply of just "..." counts as declining: it is not shown or saved, and the turns end.
- **Memory is checked on both sides.** The backend checks every memory proposal (including the live model's) before returning it. `MemoryStore` checks it again before replacing the file: right character and request, revision is exactly base + 1, the processing cursor is the last event sent, every cited event was actually sent or already cited, scopes are valid, and the text fits the caps (400 per entry, 3,000 total).
- **How memory updates flow.** History is saved first; then `MemoryStore.request_update(id)` sends the events after `last_processed_event_id` that the character heard (up to 24 at a time). One update runs per character at a time. If it fails, the old file stays, the events stay pending, and it retries after 20 s. On launch it resumes any pending events, so a crash mid-update loses nothing. A new chat request waits for that character's in-progress update, so replies always use the newest memory.
- **Mock replies quote one memory entry** ("I remember: …"), so you can see memory working without a live model. History → Memory shows each character's current memory, revision, pending count, and last error.
- **The backend never logs dialogue or memory, and never touches save files.**

## Acceptance criteria report

Every check ID comes from SPEC §10/§12.2. Status as of 2026-10-29, commit `8467900`.

**What "mock smoke test" means below:** this was observed in the real Godot client on macOS (Godot 4.7.2, Apple M2), with the backend in mock mode. The evidence is the automated `client/tests/smoke_test.gd` plus its screenshots. SPEC §10 only accepts a play session in the **Windows build with a live model**, so these items stay NOT RUN until that happens.

| ID | Requirement (short) | Status | Evidence so far / remaining work |
|---|---|---|---|
| 10.1-1 | Open Windows build, enter home + mining area | NOT RUN | Windows build exported (`build/windows/Naevia.exe`). Its data package was run on macOS and showed the home and mining area. Needs a run on a Windows PC |
| 10.1-2 | Coherent tile/character proportions | NOT RUN | 16 px tiles and a 20×42 player collider; the scene is assembled from Ryan's art and matches his `scene_direction.png` layout. Needs an owner's visual sign-off |
| 10.1-3 | Move, jump, animated walk + mining | NOT RUN | Mock smoke test: walk animation plays while moving, the mine animation plays while holding, crack frames advance with progress, stone chips burst when a tile breaks |
| 10.1-4 | Mine, buy 3 furniture types, place/move/store | NOT RUN | Mock smoke test: 3 stone mined → table bought and placed; chair and lamp placed; table moved; chair stored and placed again without paying |
| 10.2-1 | Pigeon arrives, blacksmith visits; click to talk | NOT RUN | Mock smoke test: both arrive (timer or Contacts/Dev), and clicking each opens the right conversation. Send is a button; Enter is optional |
| 10.2-2 | Replies in attached bubbles, no sidebar | NOT RUN | Bubbles anchor above the pigeon or the speaking character and have a tail. In group chat both bubbles stay readable (moved sideways when there's no room above). There is no sidebar |
| 10.2-3 | Compact/wrapping/segmented bubbles on screen | NOT RUN | Short text shrinks the bubble, long text wraps and splits at sentence boundaries ("click for more 1/3"), and bubbles are clamped on screen. Chinese text has **not** been checked: the project owner decided on 2026-10-30 not to bundle a Chinese-capable font for this phase (proposal P12) |
| 10.2-4 | Click field, type, Send; no movement/mining leak | NOT RUN | Mock smoke test: pressing D while the field is focused types into it and doesn't move the player; clicking Bag buttons doesn't place furniture behind them |
| 10.2-5 | Play while waiting; history viewable | NOT RUN | Mock smoke test: the player walks while a reply streams. The History panel lists each character's exchanges |
| 10.3-1 | Both characters answer unscripted via live API | NOT RUN | Live check on macOS (gpt-4o-mini): both characters answered new messages in the game, streaming into their bubbles (first text after 0.5–3 s). Not yet in the Windows build |
| 10.3-2 | Distinct voices, own lives | NOT RUN | Live: the witch is dry and wry ("Statistics can be a tricky beast"), the blacksmith warm and plain. Both bring up their own lives unprompted (the stubborn sideways plant, the grinding wheel) |
| 10.3-3 | Brief, non-generic replies | NOT RUN | Live replies were 1–3 sentences and responded to what was said. The group answers to "Dean's List" leaned toward stock congratulations ("That's great news! Congrats!") |
| 10.3-4 | No guilt/penalty for ignoring | NOT RUN | An ignored visitor leaves after 60 s without saying anything, and no relationship stat exists. Live wording still unchecked |
| 10.4-1 | Witch uses a told detail later | NOT RUN | Mock smoke test: after the player mentions exams, the witch's memory file records it (private, learned from the player), and her next reply includes "I remember: … exams …". Live: after being told about a Thursday statistics exam, the witch's memory recorded it as a private fact. Asked later "what should I do the night before?", she answered for an exam night ("A good night's sleep is worth more than cramming") without naming the date |
| 10.4-2 | Recall survives restart | NOT RUN | Mock smoke test: after a rebuild from disk with memory caches cleared, the witch's memory reloads from her file and her reply still recalls the exams |
| 10.4-3 | Blacksmith not given witch's private memory | NOT RUN | Mock smoke test: the blacksmith's memory holds his own conversation and nothing about the exams; the witch's holds nothing from his. Each request carries only the speaker's own memory file, which the test confirms by inspecting the request bodies |
| 10.4-4 | Exam-finished update reflected | NOT RUN | Not yet tried live. The memory instructions now ask the model to update or remove ongoing situations when they change |
| 10.5-1 | Invite Both; shared announcement | NOT RUN | Mock smoke test: Invite Both brings both into the house and opens group mode; "I made the Dean's List!" gets replies from both. Needs a live model to judge whether replies fit |
| 10.5-2 | Characters address each other, correct bubbles | NOT RUN | Mock smoke test: the witch addresses the blacksmith (`@to:`), he answers, and each reply is in its own speaker's bubble. History shows "Witch → Blacksmith". Live (backend check, 1 of 3 group trials): the blacksmith answered the witch's remark about her plant (`@to:witch`) and she asked him about his grinding wheel (`@to:blacksmith`). In the in-game live run, both answered the player instead. Character-to-character talk happens, but not every time |
| 10.5-3 | Learns shareable detail from other character | NOT RUN | Mock smoke test: after the group closes, the witch's memory has the blacksmith's grinding-wheel news (shared, learned from the blacksmith), and it is still there after a restart |
| 10.5-4 | Group doesn't expose private memory; ends turns | NOT RUN | Mock smoke test: both group requests hold only shared memory entries (no exams, no bellows). Characters that keep handing off stop after 3 turns, and a new player message cuts queued turns short |
| 10.6-1 | Everything persists across restart | NOT RUN | Mock smoke test: stone, furniture, mined cells and player position all survive a rebuild from disk, and history is saved as JSONL. Both memory files reload from disk |
| 10.6-2 | Responsive during replies + memory work | NOT RUN | Streaming is polled without blocking, and the player moved during a reply. Memory updates are non-blocking HTTP requests; with memory updates failing, chat still completed |
| 10.6-3 | Clear failure state, retry, no duplicates | NOT RUN | Mock smoke test: with the backend unreachable, a bubble says "Can't reach the local backend… Is it running?" and offers Retry. Retry completed the exchange with exactly 2 history events (no duplicate player message) |
| 10.7-1 | Another dev can follow setup to run everything | NOT RUN | Backend, client, live and export steps verified on macOS and written above. The Windows run steps are written but untested |
| 10.7-2 | Config examples, pinned deps, no secrets | NOT RUN | `.env.example`, `requirements.lock` and Dev contact triggers exist; `.env` is gitignored. Known issues are listed below |

**Summary: 0 / 26 PASS.** 21 checks have supporting evidence from macOS: mock smoke tests, plus live runs with `gpt-4o-mini` for the conversation checks. Milestones A–D are built and live mode works. The Windows build is exported (milestone E, first half). SPEC §10 only counts play sessions in that build, so what remains is running it on a Windows PC with the live backend and recording the results here.

### Known issues and placeholders

- **No CJK font is bundled, by decision.** On 2026-10-30 the project owner (April Gong) decided to leave out SPEC §3.3's Chinese-capable font for this phase (proposal P12). Godot's default font renders English. Chinese text may show as missing glyphs.
- **The Windows build has not been run on Windows.** It was exported and its data package tested on macOS. There is no Windows machine here and no Wine.
- **Mock memory only appends.** The mock records each thing the player said as an experience and drops the oldest when over 3,000 characters. Real consolidation (facts, ongoing situations, merging duplicates) depends on the live model and is untested.
- **The smoke test fights macOS focus.** macOS gives focus back to the launching app about 3 s into a run, and Godot releases held buttons on focus loss. The test retakes focus and re-presses held buttons. If you use the computer during a run, focus keeps moving and mining or click checks can fail. The test then prints how many times focus was lost; rerun without touching anything.
- **Mock group text reads oddly** ("I'm restoring … he found … myself"), because the mock pastes the profile's third-person situation into a first-person sentence. Live replies don't do this.
- **The witch only appears in person during Invite Both.** Privately, she is reached by pigeon, as the spec describes.
- **Furniture placement is forgiving.** It drops onto the first solid floor under the cursor, anywhere in the world, not just inside the house.
- **The player's own messages don't appear as a bubble.** They show only in History.
- **Mined tiles stay gone.** Only the Dev "Reset resources" button restores them.

## Next steps for whoever picks this up

1. Live model quality: try 10.4-4 (tell the witch the exam is over) and watch whether character-to-character talk happens often enough with `gpt-4o-mini`. If not, try a stronger model. Only `.env` changes.
2. **Finish milestone E on a Windows PC:** set up the backend with the PowerShell commands, run `Naevia.exe`, do the two acceptance sessions in SPEC §10 with a live model, and fill in the acceptance table. Report anything that only breaks on Windows (fonts, paths, firewall prompts for the backend).
3. (Deferred by the owner) Bundle an English/Chinese font with a license that allows redistribution.

See [HANDOFF_REPORT.md](HANDOFF_REPORT.md) for an assessment of the inherited work, and [prompt_log.md](prompt_log.md) for the AI-assisted development log.
