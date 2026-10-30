# Naevia — Demo 1 Implementation Specification

Version: 0.7 | Status: Visual assets delivered and file checks passed; game implementation pending; Demo 1 scope unchanged

This is the single handoff document, published as root-level `SPEC.md` on GitHub. A developer must be able to implement, run, demonstrate, and record acceptance of Demo 1 using this file plus the supplied visual assets. No PRD, README, separate design document, conversation history, or external acceptance report is required. Source code and visual assets are deliverables, not additional specification documents. Setup instructions and actual acceptance results must be maintained in sections 11 and 12 of this same file.

## 1. Goal and Scope

Build the playable Godot frontend from the project's visual handoff, then connect the API backend and automatic local memory. Visual production is separate from this specification and may be delivered in a later repository commit. The next developer should inspect the latest completed asset delivery using section 3.3, then follow the implementation milestones in section 8. Do not restart visual concept development as a prerequisite to implementation.

Naevia is a companionship-focused pixel game in a private world. The player gathers materials and furnishes a small home while spending time with AI characters who have distinct personalities, their own current lives, and independent memories. Conversation is part of play: characters may visit or send a messenger, and the player can move and gather while waiting for a reply. Replies appear in the world, not in a permanent chat sidebar. Ignoring an invitation or taking time away causes no relationship penalty. Characters should show situational interest rather than constant praise.

Demo 1 includes one fixed home, a small mining area, furniture placement, the witch and blacksmith, clickable speech bubbles, independent persistent memories, and a three-person conversation.

Keepsakes, expansion, birthdays, official gifts, local inference, and large-world simulation are deferred. Numeric values below are adjustable implementation defaults, not measured results.

The delivered result must be a playable Windows game with a local backend and live cloud AI, not a visual mockup, web page, prerecorded interaction, or mock-only chat demo. A developer must demonstrate movement, mining, furniture arrangement, private and group conversation, independent cross-session memories, and save recovery in the same application. This revision consolidates handoff instructions without reducing the feature scope or the observable acceptance criteria in section 10. Existing artwork is an implementation input, not evidence that gameplay or required animation has been completed.

## 2. Tools and Responsibilities

- **Client:** Godot 4.7 stable, standard build, GDScript, Compatibility renderer. Use matching Windows export templates. Record the exact editor version in section 12.
- **Backend:** Python 3.12, FastAPI, Uvicorn, Pydantic, HTTPX. Lock dependencies when scaffolding.
- **Model adapter:** HTTP chat-completions transport for an OpenAI-compatible provider. This names the protocol, not the chosen model vendor. Endpoint, model ID, and credentials are configuration.
- **Persistence:** Local JSON saves and character memories; JSONL dialogue history. No SQL, vector database, or embedding model for Demo 1.
- **Assets:** Reuse the repository's existing visual references, previews, palette, and exported PNGs. Use LibreSprite or equivalent tools only for missing assets, pixel cleanup, and animation alignment; use Godot's TileSet editor for tile collision and assembly. Preserve the established character designs and visual direction.
- **Verification:** pytest for backend and memory contracts; manual Godot playthrough for visual interaction.

Godot owns gameplay, dialogue coordination, and all local file reads/writes. FastAPI composes prompts, calls the model, normalizes responses, and returns proposed memory updates. The cloud model never searches the player's disk.

For Demo 1, run the Godot client and FastAPI backend on the same Windows computer. Bind the backend to loopback (`127.0.0.1`) and keep saves local. No hosted deployment, accounts, demo access tokens, or cloud-save database are required. Keep provider credentials in local backend environment configuration, outside client files and version control. Live AI requests still go to the configured cloud provider and require internet; mock mode can run offline. Local model inference remains out of scope.

### Repository structure

```text
Naevia/
  SPEC.md
  art/
    references/
    previews/
    source/
    export/
      characters/
      manifest.json         # Add or validate during asset integration
  client/
    project.godot
    scenes/
    scripts/
    assets/
    data/visuals.json
    data/items.json
    data/tiles.json
    data/characters/
    data/furniture.json
  server/
    app/main.py
    app/schemas.py
    app/provider.py
    app/prompts.py
    tests/
    .env.example
    requirements.lock
  build/windows/
    Naevia.exe
    Naevia.pck              # If resources are not embedded
```

The published handoff contains `SPEC.md` plus the completed visual package under `art/`. The client, server, configuration examples, tests, and Windows build above are implementation outputs to create. Do not claim they already exist. No additional Markdown files are required for implementation handoff or acceptance. The handoff includes runtime exports, previews, source visual references, the palette, and the asset validation report; intermediate generation images and preparation scripts are retained locally and are not required to import these ready-to-use exports.

## 3. Frontend Foundation

### 3.1 Scene and modules

Create World.tscn containing:

- TileMapLayer nodes for background walls, solid terrain, and mineable resources.
- A CharacterBody2D player with CollisionShape2D, AnimatedSprite2D, and Camera2D.
- Separate witch, blacksmith, and pigeon scenes, each with an Area2D click target.
- A furniture container with individual placed-object nodes.
- A CanvasLayer for bubbles, reply input, inventory, and contact controls.

Implement these scripts with clear ownership:

- PlayerController: movement and animation.
- MiningController: mining progress and resource removal.
- FurnitureController: purchasing, placement, moving, storing.
- ConversationCoordinator: participants, speaker order, and conversation IDs.
- BubbleController: speaker anchors, wrapping, segments, and input focus.
- ApiClient: ordinary requests and streamed replies.
- MemoryStore: per-character files and queued updates.
- SaveManager: world state and safe file replacement.

### 3.2 Scale and camera

Use Terraria's base proportions: a tile is 16 × 16 game pixels, representing approximately 0.61 meters / 2 feet. The standard player collision box is 20 × 42 pixels; standing clearance is roughly three tiles. Match furniture and architecture to these proportions. Sprite canvases may extend beyond collision bounds.

Start with a 640 × 360 world viewport, nearest-neighbor texture filtering, integer display scaling, and letterboxing. Initial window: 1280 × 720. Render dialogue UI at display resolution with a bundled font covering English and Chinese.

### 3.3 Art and animation

#### Existing visual handoff

The completed visual delivery contains 35 runtime PNGs and `art/export/manifest.json`: 10 character sheets, 11 tiles, 3 house props, 3 furniture images, 4 inventory icons, 2 effects, and 2 backgrounds. Use the following paths as the visual baseline:

- `art/references/scene-style-v1.png` and `art/references/characters-v1.png`: source visual references.
- `art/previews/scene_direction.png`: 640 × 360 scene composition defining the home's cutaway presentation, adjacent mining area, palette, and environmental style. This is a reference image, not a playable level or a source of collision data. Furniture, characters, and mineable terrain must become independent game objects.
- `art/previews/character_lineup.png` and `character_lineup_4x.png`: character proportions and identity; the 4× version is for inspection, not a runtime sprite sheet.
- `art/previews/palette.png` and `art/source/palette.json`: shared color direction.
- `art/export/characters/player_idle.png`, `witch_idle.png`, and `blacksmith_idle.png`: RGBA PNGs, each 96 × 64, containing two horizontal 48 × 64 frames.
- `art/export/characters/pigeon_idle.png`: RGBA PNG, 64 × 32, containing two horizontal 32 × 32 frames.

The exported character sheets use no frame spacing. The existing export process places humanoid feet at frame coordinate `(24, 60)` and pigeon feet at `(16, 28)`; verify those anchors visually when importing. Use the native-size files from `art/export/`, not the higher-resolution generation sources. Preserve source artwork and previews. `art/source/` contains preparation scripts and generation provenance, not game runtime dependencies; the Windows build must not depend on their machine-specific paths.

Visual production is complete for this package. The 35 runtime PNGs passed file-contract validation, but have not yet been imported into a running Godot game. Use the delivered manifest and map the actual exports to the requirements below before introducing substitutes. No separate art brief or delivery document is required. If an integration gap is found, record it in section 12; do not remove a Demo 1 requirement. Art integration must not change the feature scope or acceptance checklist.

#### Delivered visual details

- `art/previews/scene_direction.png` is now a 640 × 360 composition assembled from the actual runtime exports; `scene_direction_2x.png` is its nearest-neighbor 1280 × 720 preview. Neither is a playable level or a substitute for individual world nodes.
- `art/previews/animation_contact.png` and `animation_contact_2x.png` show the ten character actions frame by frame. Use manifest playback rates: idle 2 fps; player walk 8 fps; witch/blacksmith walk, player mining, and pigeon flight 6 fps. The jump pose is static. Left-facing sprites are mirrored by the engine.
- Standing humanoid feet use `(24, 60)` and pigeon feet `(16, 28)`. The jump pose intentionally raises the visible feet inside the same canvas; do not shift the character node to compensate for its image bounds. World movement, flight paths, collision, and visual anchors are separate concerns.
- `effects/mining_cracks.png` has three 16 × 16 frames and manifest `playback: manual_progress`, `fps: 0`, `loop: false`. Select frames by mining progress; do not autoplay the crack sheet. `effects/stone_chip.png` is a 4 × 4 particle image.
- The landscape layer can repeat horizontally; the sky includes a sun and should not repeat indefinitely by default. Tile previews demonstrate the supplied straight-edge/limited platform set, not a complete autotile solution for arbitrary terrain.
- The door is an open 32 × 48 frame with a 22 × 44 transparent opening. Configure passability explicitly; the PNG itself supplies no collision. Furniture is nonblocking for this prototype.
- `art/previews/ui_direction.png` and `scene_ui_preview.png` guide native Godot controls. At a 1280 × 720 display, start with 20–22px body text, 16–18px secondary text, 16px horizontal bubble padding, 12px vertical padding, and a 44px minimum input/button height. Panel/background `#f4e9d2`, border `#4b382d`, text `#352c2a`; button normal/hover/pressed/disabled colors are `#eadbb9`, `#d4d8a5`, `#9ea77c`, `#c9c4b6`. Runtime UI PNGs are intentionally absent because the developer constructs these controls with live text.
- Illustrations were generated with imagegen and normalized into native RGBA PNGs. No layered Aseprite source or redistributable font file is included. UI previews use a system font for demonstration only; bundle a separately verified English/Chinese font for the actual game.
- `art/source/validation-report.json` records 35 assets, zero file-contract errors, per-asset SHA-256 values, frame bounds, and the checks performed. This validates import inputs, not runtime gameplay or artistic acceptance. Do not depend on the art producer's original absolute paths or regeneration scripts.

#### Runtime integration and ownership

1. Inspect exported PNG dimensions, transparency, frame layout, orientation, and baseline. If `art/export/manifest.json` exists, validate it against actual files; otherwise create it as part of integration. Record stable visual IDs, relative paths, frame dimensions/count, playback rate, looping, and anchors.
2. Place validated runtime assets under `client/assets/`, preserving traceable paths back to the art export. Build `SpriteFrames` resources and character scenes in Godot. Use nearest-neighbor filtering and match the scale in section 3.2; keep collision bounds independent of transparent sprite canvas size.
3. Build a small editable level from separate background, walls, solid terrain, resource tiles, furniture, and character nodes. Do not display a flattened scene preview as the interactive world. Configure TileSet collision and mineable cells explicitly.
4. Keep visual lookup in `client/data/visuals.json`, keyed by stable visual IDs referencing Godot resources. Keep gameplay definitions in `items.json`, `tiles.json`, and `furniture.json`. An item definition specifies its icon visual ID; a tile definition specifies its tile visual ID, mining rules, and drop item ID. Do not infer gameplay behavior from PNG filenames or pixels.
5. World saves reference stable definition IDs and object positions, not absolute artwork paths or sprite image data. Definitions and visuals ship with the client; changing an asset path should only require updating its visual mapping, not rewriting player saves.

For example, a stone resource cell references `tile.stone`, whose definition references a stone visual and drops `item.stone`. Mining is local game logic: remove the resource cell, add material, update rendering, and save. The backend and AI do not choose tile textures or authorize ordinary mining and placement.

#### Required coverage and remaining assets

Complete the existing scene direction with reusable ground, grass, stone, flooring, walls, door, table, chair, lamp, and two background layers. Provide matching inventory icons. Use the existing player, witch, blacksmith, and pigeon designs throughout; add any missing art in the same style rather than replacing the established designs.

PNG is the runtime exchange format. Characters, furniture, item icons, and overlay effects require transparent backgrounds. Tiles use a 16 × 16 grid; furniture dimensions and placement footprints use whole tiles. Prefer the delivered manifest for frame layout and anchors, validated against actual files. Initial defaults for missing metadata are 48 × 64 humanoid frames with feet at `(24, 60)`, 32 × 32 pigeon frames with feet at `(16, 28)`, 48 × 32 table, 16 × 32 chair, 16 × 48 floor lamp, and 16 × 16 inventory icons. These are import defaults, not permission to distort an approved asset. If the final art uses a different valid frame layout, adapt resource metadata while preserving the world proportions in section 3.2.

Animation targets remain four-frame player walking and mining, two-frame pigeon flight, character idle poses, and short walk cycles for visitors. Keep foot anchors consistent with the imported idle sheets. Use `AnimatedSprite2D` for playback. Small debris can use `GPUParticles2D`. No prerecorded video is needed.

Missing assets may use explicitly tracked temporary placeholders during development so gameplay implementation can proceed. Before final acceptance, required walking/mining/contact animations and essential world/furniture visuals must be present and coherent, as required by section 10. A static idle sheet or moving a static picture does not by itself satisfy the walking or mining animation requirement.

Build conversation UI using Godot controls with live text, adaptive bubbles, and independent anchors. A UI preview may guide styling but must not replace functional input, buttons, or readable English/Chinese text.

### 3.4 Gameplay controls

- A/D moves; Space jumps.
- Hold left mouse on a resource tile within four tiles to mine. Start at one second per tile; each tile yields one stone.
- Mining removes that resource cell and its collision, exposing the background. Only marked resources are mineable; the house stays fixed.
- An inventory menu offers a table, chair, and lamp. Initially each costs three stone.
- Selecting an item enters placement preview. Left click places; right click cancels. Snap placement to the tile grid for Demo 1.
- Arrange mode selects existing furniture to move or store. Stored items can be placed again without paying twice. Furniture does not block walking in this prototype.
- Provide a development action to reset resources.

UI consumes clicks before gameplay. Text focus disables movement shortcuts. Saving follows material and furniture changes; player position saves on a short debounce.

## 4. Conversation Interaction

### 4.1 Contact and invitations

After initial play, a timer brings a pigeon near the player. A separate timer can bring the blacksmith to the door. Allow only one unsolicited invitation at a time, with configurable intervals. Ignoring an invitation causes no relationship penalty.

Click the pigeon to talk remotely with the witch; anchor her replies to the pigeon. Click the blacksmith to talk locally; anchor his replies above him. A small Contacts control offers Witch, Blacksmith, and Invite Both. Invite Both brings the two characters into the house scene and starts group mode.

Add development buttons to trigger contacts immediately.

### 4.2 Input and bubble sequence

1. Click a messenger or character to open the conversation and reply control.
2. Click the reply field to type; click Send to submit. Enter is not required.
3. Save the player message, release text focus, and show a waiting indicator.
4. Stream the response into a bubble while movement and other gameplay remain available.
5. Wrap text automatically and split long replies at sentence boundaries. Click to advance overflow segments; retain the last segment until dismissal or a new reply.
6. An on-demand History control shows prior dialogue. Do not create a permanent chat sidebar.

Bubble font size, padding, width, height, and segment length live in one configurable UI resource. Start around 320 display pixels maximum width and 160 maximum height. Short messages shrink to fit.

Convert speaker world positions into CanvasLayer coordinates each frame. Clamp bubbles to screen bounds and offset overlaps. Only the current speaker needs a full-size reply bubble.

Allow one pending player submission per conversation. Closing or changing conversations cancels remaining AI turns after the current response. Use conversation IDs so a late reply cannot appear in a different conversation.

### 4.3 Character profiles and group turns

Create editable JSON profiles with personality, speaking style, background, current personal situation, and starting relationship.

Starter defaults:

- Witch: elderly, observant, dry humor, values small pleasures; currently tending an unusual garden.
- Blacksmith: practical, warm, direct; currently restoring an old workshop tool.

They begin as familiar acquaintances. Do not invent past shared events. These writing defaults can change without altering code. Replies usually contain one to three sentences and may include the character's own life. Avoid repetitive praise.

ConversationCoordinator chooses turns. In private mode, use the selected character. In group mode, prefer a character explicitly addressed by the player; otherwise alternate the first responder. A reply can nominate another present character to answer. Allow at most three character turns per player message, then wait for the player. A new player message cancels queued turns after the current turn.

Each speaker receives only their own eligible memory and the dialogue they can hear. Characters can address each other or decline to add anything. The announcement example must emerge from these rules, not a fixed script.

## 5. Backend and Model Integration

### 5.1 Configuration

Server environment:

- NAEVIA_PROVIDER_BASE_URL
- NAEVIA_MODEL
- NAEVIA_PROVIDER_API_KEY
- NAEVIA_MODEL_MODE=mock or live

Client configuration specifies a local backend URL, initially `http://127.0.0.1:8000`. Keep real provider credentials out of client files and the repository. Mock mode requires no provider account. Hosted access configuration is deferred beyond Demo 1.

ProviderAdapter exposes stream_reply(context) and update_memory(context). Use HTTPX for the external HTTP connection. Unsupported provider-specific protocols require an adapter; do not assume every provider implements the selected transport identically. Validate the selected provider/model with a smoke test before live integration.

### 5.2 Endpoints

- GET /health: returns service status and mock/live mode.
- POST /v1/chat: streams one character turn.
- POST /v1/memory/update: returns a complete validated replacement memory for one character.

Use Pydantic schemas for request and response bodies. The service remains stateless with respect to game saves; no file-access endpoint is needed.

A chat request contains request_id, conversation_id, speaker_id, participants, profile, memory, recent_messages, and scene_context. Messages carry event_id, speaker, addressee, audience, and text. Audience is assigned by game logic.

Compose prompts in this order: character instructions, profile, authorized memory, observable scene context, recent dialogue. Private requests never include the other character's private history. Group requests include the shared gathering transcript.

### 5.3 Streaming contract

Normalize provider output into newline-delimited JSON using FastAPI StreamingResponse:

```json
{"type":"text_delta","request_id":"r1","text":"That sounds"}
{"type":"text_delta","request_id":"r1","text":" like good news."}
{"type":"done","request_id":"r1","speaker_id":"witch","addressee":"player"}
```

A terminal error event contains the request ID and a displayable message. In Godot, poll HTTPClient and read_response_body_chunk without blocking the game loop. Buffer raw bytes until complete newline-delimited records arrive, then decode UTF-8 and parse JSON. Use HTTPRequest for health and memory requests.

Ask the model for an optional first-line recipient marker such as @to:blacksmith. Buffer and remove this line before displaying text. Validate it against participants; missing or invalid markers default to the player. Normalize nonstreaming provider replies into the same event format if necessary.

Mock mode returns deterministic streamed replies and valid memory snapshots. On failures preserve the player's message, offer retry, and keep gameplay running. Only commit a completed character turn to history.

### 5.4 Memory update contract

A memory request contains `request_id`, `character_id`, `base_revision`, the character's current `memory`, and `new_events` they actually heard. The response contains `request_id`, `character_id`, `base_revision`, and a replacement `memory` using section 6's schema. The client accepts it only if the character and base revision still match; the replacement revision must be `base_revision + 1`.

Source event IDs must refer to supplied authorized new events or previously validated sources retained in the old memory. Reject invented sources, invalid scopes, oversized text, missing required fields, and changes to another character's memory. The response's processing cursor must correspond to the processed authorized events. On validation failure retain the old snapshot and leave the affected events pending. The backend is stateless: it returns proposals and never writes local save files.

## 6. Automatic Local Memory

### 6.1 Storage

Godot reads and writes files under user://saves/default/:

```text
world.json
characters/witch.memory.json
characters/blacksmith.memory.json
history/witch.jsonl
history/blacksmith.jsonl
history/group.jsonl
```

Static character profiles stay in res://data/characters/. Separate history from concise current memory. No SQL queries or vector search are required in this demo.

Memory shape:

```json
{
  "schema_version": 1,
  "character_id": "witch",
  "revision": 2,
  "last_processed_event_id": "e12",
  "facts": [],
  "ongoing": [],
  "experiences": []
}
```

Each entry has id, text, source_event_ids, learned_from, and share_scope (private or shared). Facts describe stable knowledge; ongoing describes current situations; experiences summarizes meaningful exchanges. Initially cap combined memory text at approximately 3,000 characters per character and consolidate during updates. Retain raw history separately.

### 6.2 Read, generate, update

1. Load the speaking character's memory and last 12 relevant messages. Await any pending memory update for that character before assembling context; gameplay remains active.
2. Send that context to /v1/chat and display the streamed reply.
3. Append the completed exchange to history with stable event IDs.
4. In the background, send that character's current memory, revision, and newly heard events to /v1/memory/update.
5. The model proposes a replacement snapshot, preserving valid facts, updating changed situations, and merging duplicates. It must retain source links and cannot invent events.
6. Validate schema, character ID, base revision, sources, and text limits. Write a temporary file and replace the old snapshot after validation.

Memory processing is automatic, with no routine prompts or explicit “remember this” command. Model generation proposes the changes; code controls files and persistence.

Serialize updates per character. Reject stale revisions, retain the old file on error, and retry unprocessed events. Event IDs and processing cursors prevent duplicate application. Persist history before requesting an update so a restart can recover pending work.

### 6.3 Group knowledge

After group turns finish, update each participant from their own existing memory plus the events they heard. Never copy the witch's memory into the blacksmith's update input.

Private entries inform private conversations. For Demo 1 group prompts, withhold private entry content and supply shareable memory plus the current public transcript. Information spoken publicly can become shared knowledge for listeners. Keep the original speaker as the knowledge source.

## 7. World Persistence

world.json stores schema_version, player position, remaining resource tiles, material counts, stored furniture, and placed object IDs/positions. Use stable IDs, temporary-file replacement, and the same save-directory ownership as memory.

Local storage does not imply local AI processing. The local backend and configured cloud provider receive the selected context sent for a live request. Do not log full dialogue or memory by default in the backend.

## 8. Implementation Milestones

### A. Existing visuals to playable frontend with mock dialogue

Begin by inventorying the latest `art/export/` delivery, validating the available character sheets, and importing the existing palette and visuals into a new Godot project. Build one small scene matching the current reference direction, using separate objects and tiles. Establish stable definition/visual IDs and validate collision, pixel scale, foot alignment, and draw order before expanding interaction.

Then implement movement, mining, inventory and furniture controls, clickable contacts, adaptive bubbles, and a local mock reply source. Cover both witch and blacksmith scenes visually from the start; independent persistent memories are added in milestone C. Fill asset gaps incrementally without pausing the whole build for a new concept phase.

Complete when a player can gather stone, obtain/place/move/store furniture, click a pigeon or visitor, type and send, and receive mock replies while the world stays responsive. Maintain remaining asset gaps in section 12 of this specification; this milestone does not waive the final visual or live-AI acceptance requirements.

### B. Backend framework and live model

Implement FastAPI schemas, mock/live ProviderAdapter, health, streaming chat, and configuration examples. Connect Godot's ApiClient. Complete when a live reply displays progressively without freezing the world.

### C. Local memory

Implement per-character JSON, dialogue event history, memory updates, and queued file writes. Add the blacksmith with isolated state. Complete when both characters maintain different knowledge across restarts.

### D. Group conversation

Implement Invite Both, speaker coordination, recipient markers, shared history, and listener memory updates. Complete when one character can learn through another character's speech without access to their private file.

### E. Playable Windows handoff

Integrate the final available art delivery, replace essential placeholders, finish required animation and saving, and export Windows. Check the build against the established scene/character direction and complete the unchanged acceptance checklist in section 10 using a live model. Deliver the Godot project, backend source, locked dependencies, example configuration, Windows build, and setup instructions.

Complete section 11 with the actual validated installation, startup, model configuration, and export instructions. Complete section 12 with the actual implementation status, asset gaps, known issues, test results, and per-item acceptance outcomes. Keep this material in the same root-level `SPEC.md`; do not require another Markdown document to operate or assess the delivered demo.

## 9. Verification

Add focused checks for request schemas, mock event output, isolated character contexts, memory revisions, and duplicate events. Manually verify bubble positioning, input focus, streamed text, mining, placement, and save recovery. Record actual results; the document itself is not proof of implementation.

Acceptance playthrough:

1. Gather stone, obtain furniture, and place it.
2. Privately tell the witch about preparing for exams.
3. Restart: the witch remembers; the blacksmith has not learned that exchange.
4. Invite both and announce making the Dean's List.
5. Let them respond and talk to each other, without scripting a required reaction.
6. Restart and verify updated individual memories and the saved room.

Model vendor, exact model ID, and final character writing remain tuning/configuration choices. The current artwork and palette provide the visual baseline; only necessary adjustments for integration and readability should be made during implementation. These choices do not block frontend and backend mock work. Select and record a working cloud model before live milestone B is complete.

## 10. Demo 1 Acceptance Checklist

This is the product acceptance checklist for the first playable demo. Pass items by playing the Windows build with a live model, not just by reading code or watching mock replies. The developer should record pass/fail and any remaining issue for each item. Natural wording may vary; exact scripted sentences are not required.

### 10.1 A playable, coherent pixel world

- [ ] I can open the Windows build using the supplied instructions and enter the home and adjacent mining area.
- [ ] The world uses a horizontal 2D view with consistent Terraria-style tile and character proportions. Characters, terrain, furniture, and backgrounds form a coherent pixel-art scene.
- [ ] I can move and jump. Walking and mining have visible animation; mining is more than a static image with an inventory counter.
- [ ] I can mine stone, obtain at least three furniture types, and place, move, and store them. The result is visible in the room, and furniture can be placed again after being stored.

### 10.2 Click-to-talk bubbles

- [ ] A pigeon can arrive and the blacksmith can visit. I can click either to start the corresponding conversation without pressing Enter.
- [ ] Replies appear in bubbles attached to the correct character or messenger, not in a permanent chat sidebar.
- [ ] Short text produces a compact bubble; longer text wraps or splits into readable segments. Bubbles do not run off screen or become unreadable when the camera moves.
- [ ] I can click the reply field, type, and click Send. Typing does not move the player; clicking UI does not mine or place items behind it.
- [ ] I can resume movement and gathering while waiting for a reply, then read it and respond. Previous dialogue can be revisited.

### 10.3 Real AI conversation and distinct characters

- [ ] Both characters answer new, unscripted messages through the live API. The core demo is not limited to predefined responses.
- [ ] The witch and blacksmith have recognizably different voices and can discuss their own current lives as well as mine.
- [ ] Ordinary replies are usually brief. Characters respond to what I actually say, rather than turning every exchange into generic praise.
- [ ] I can ignore a contact invitation or stop chatting and continue playing without guilt messages or relationship penalties.

### 10.4 Automatic, independent memory

- [ ] I tell the witch one specific detail, such as an upcoming exam date or a favorite food. Later, she can use that detail when relevant without asking me to save it.
- [ ] After closing and reopening the game, the witch can still recall the detail. No explicit memory command or routine confirmation was needed.
- [ ] Before I share it elsewhere, the blacksmith does not claim knowledge of the detail told only to the witch. Inspecting request context confirms that he was not given her private memory.
- [ ] When I tell the witch that the exam is now finished, her later responses reflect the update instead of repeatedly treating it as upcoming.

### 10.5 Shared conversation and learning from others

- [ ] Invite Both brings the witch and blacksmith into a shared interaction. I can announce something, such as making the Dean's List, and receive context-appropriate responses.
- [ ] Characters can address and answer each other through correctly attributed bubbles. At least one live exchange demonstrates this, without a hard-coded dialogue script.
- [ ] A character learns a new, shareable detail spoken by the other character and can recall it later, including after restarting. A character's own life update can be used to test this without exposing my private conversation.
- [ ] Group participation does not grant access to either character's full private memory. The conversation returns control to me rather than running indefinitely.

### 10.6 Continuity and basic reliability

- [ ] After restarting, my materials, furniture inventory, room arrangement, conversation history, and character memories remain available.
- [ ] The world stays responsive during live replies and background memory processing. An ordinary play session can include gathering, decoration, private chat, and group chat without crashing.
- [ ] If the API is unavailable, I see a clear failure state, retain my message for retry, and can continue basic gameplay. Retrying does not duplicate a completed exchange.

### 10.7 Handoff

- [ ] Another developer can follow section 11 of this SPEC to open the client, run the local backend in mock mode, configure live AI, and produce the Windows build.
- [ ] The delivered source includes configuration examples, dependency versions, development contact triggers, and a clear list of placeholders and known issues. Real provider credentials are absent from source and client builds.

### Acceptance session

Use one short session to connect the checks: gather and decorate; privately tell the witch an exam detail; restart and check separate knowledge; update the exam status; invite both and announce Dean's List; observe a character-to-character exchange; restart and check what each character remembers.

Run this once from a fresh save and once with an existing save. Record the machine and model configuration, noticeable reply delays, and any failed items. Automated checks support this session but do not replace the actual playthrough.

Demo 1 is accepted when these checks pass and the owner is satisfied with the visual coherence, character distinction, and comfort of alternating play and conversation. Final art polish, keepsakes, expansion, celebrations, local inference, and a larger world are not acceptance conditions for this demo.

## 11. Setup, Running, and Windows Delivery

The instructions below define the required implementation contract. No application or successful execution is claimed by this document. The implementing developer must verify these steps on the delivered revision, correct paths/options here if necessary, and record actual versions and outcomes in section 12. Do not delegate these instructions to a README.

### 11.1 Development setup and mock mode

Prerequisites: Windows, Godot 4.7 standard with matching export templates, and Python 3.12. `requirements.lock` must contain pinned, installable backend dependencies, including support for loading `.env` with Uvicorn. Keep `.env`, provider secrets, virtual environments, Godot import caches, and personal saves out of version control; provide `server/.env.example` with non-secret examples.

From the repository root, in PowerShell:

```powershell
Set-Location server
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.lock
Copy-Item .env.example .env
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --env-file .env
```

Copy `.env.example` only on initial setup; do not overwrite an existing configured `.env`. The supplied example defaults to `NAEVIA_MODEL_MODE=mock`. Verify `http://127.0.0.1:8000/health` reports healthy mock mode. Open `client/project.godot` in the matching Godot editor, use backend URL `http://127.0.0.1:8000`, and run the main scene. No provider account or internet is needed for mock dialogue and basic gameplay. The main scene, client configuration location, and any differing executable names must be recorded here by the developer.

### 11.2 Live AI

In local `server/.env`, set `NAEVIA_MODEL_MODE=live`, `NAEVIA_PROVIDER_BASE_URL`, `NAEVIA_MODEL`, and `NAEVIA_PROVIDER_API_KEY`; restart the local backend. Document whether the configured base URL includes `/v1` so the adapter does not accidentally duplicate or omit it. Keep the actual key out of this SPEC, logs, screenshots, client files, and builds.

Verify `/health` reports live mode, then send an unscripted message to each NPC and check incremental display. The chosen provider must support both reply generation and validated memory proposals through the adapter. Record the provider/model IDs and actual smoke-test outcome in section 12. Do not mark live conversation or memory acceptance passed using mock responses. If credentials are unavailable, deliver working mock mode but report live-dependent acceptance items as BLOCKED; Demo 1 is not fully accepted yet.

### 11.3 Data location and recovery

Configure the Godot project name as `Naevia`. With default Godot user-directory settings, saves are at `%APPDATA%\Godot\app_userdata\Naevia\saves\default\`, corresponding to `user://saves/default/`. If a custom directory is chosen, replace this path here with the actual location. Assets and static definitions belong to the game package; world state, history, and NPC memories belong to the writable save directory.

To test a fresh save, close the game, preserve the existing save directory as a backup, and start with a separate empty save. Do not reset a user's real save without preserving it. To test an existing save, reopen the preserved test save and verify materials, furniture, transcript, and individual NPC knowledge. Local storage does not prevent the selected context from being transmitted to the configured cloud provider in live mode.

### 11.4 Tests and export

From `server/`, run the focused backend suite with `.\.venv\Scripts\python.exe -m pytest`. Record the actual result and test scope in section 12. Use manual Godot/Windows playthroughs for visual, input, and responsiveness checks; backend tests alone do not establish acceptance.

Provide a checked-in Windows export preset named `Windows Desktop`. Export the client with the matching Godot templates to `build/windows/Naevia.exe`, including its resource package if not embedded. The developer must record the exact working export steps and output paths here after validation. Distribute backend source, pinned dependencies, `.env.example`, and client assets with the project; never bundle a real provider key.

For this local demo, an explicitly documented two-process launch is sufficient: start the Python backend as above, then run `build/windows/Naevia.exe`. A unified launcher may automate that sequence but is not a new acceptance condition. A tester should not need the Godot editor to play the exported build. If the backend is stopped or unreachable, the game must retain basic gameplay and expose a retryable conversation error.

## 12. Implementation Status and Acceptance Record

This section is the acceptance report location. The implementing developer updates it in this same SPEC; do not create a separate report or claim acceptance from a plan. Current status: visual package delivered, 35 runtime assets passed file-contract checks with zero errors, game/backend not implemented, no acceptance playthrough performed. All unchecked gameplay requirements in section 10 are NOT RUN. File validation was rerun before publishing this visual handoff.

### 12.1 Delivery and environment record

Before requesting acceptance, replace the following pending entries with actual values:

- Source revision and Windows build identifier/path: pending implementation.
- Final visual package: delivered 2026-10-28; manifest `art/export/manifest.json`, 35 runtime PNGs. File checks passed; report `art/source/validation-report.json`. Exact source revision is the GitHub commit containing this visual handoff.
- Windows version, CPU/RAM/GPU, and display scaling: not recorded.
- Exact Godot/editor/export-template version and Python/dependency versions: not recorded.
- Provider name, model ID, and mock/live mode: not selected or verified; never include a secret.
- Actual client config path, startup commands, and export steps: pending validation of section 11.
- First visible reply delay and time to complete reply, measured from Send: not measured. Record observations rather than inventing a latency target.
- Remaining placeholders, asset gaps, and known issues: no missing required runtime artwork identified in file checks; Godot integration, in-game animation continuity, layering, collision, lighting, bubble anchors, and font bundling remain to be verified during implementation.
- Backend test command, result, and relevant context-isolation/memory-recovery checks: not run.

### 12.2 Per-item outcomes

Give each checkbox in section 10 a stable identifier based on its subsection and order: `10.1-1` through `10.1-4`, `10.2-1` through `10.2-5`, `10.3-1` through `10.3-4`, `10.4-1` through `10.4-4`, `10.5-1` through `10.5-4`, `10.6-1` through `10.6-3`, and `10.7-1` through `10.7-2`. There are 26 checks; every one needs an outcome.

For each identifier append a result in this format, directly in this subsection:

```text
Check: <identifier and short requirement>
Status: PASS | FAIL | BLOCKED | NOT RUN
Mode/build: <live or mock, build identifier>
Observed: <what actually happened, including steps to reproduce a failure>
Evidence: <sanitized screenshot/recording/test reference, or concrete observation>
Remaining work: <specific issue, or none>
```

Artifacts may be referenced if available, but the observed result and remaining work must be understandable from this SPEC alone. Mark section 10 checkboxes complete only for actually passed requirements; BLOCKED and NOT RUN remain unchecked. Request-context evidence must demonstrate isolation without exposing real personal dialogue or API keys.

### 12.3 Connected acceptance sessions

Run the full session in section 10 twice: once from a fresh test save and once from an existing test save. For each run, record the date, build/model, initial save state, observed sequence, failed check IDs, and save/memory state after restarting. Include at least one live NPC-to-NPC exchange and later recall of a new shareable detail learned from the other NPC. Sharing only the player's announcement is not enough to demonstrate learning from another character.

Also interrupt the API connection to verify errors and retry behavior, and check that retry/restart does not duplicate a completed exchange. Confirm a privately shared detail is absent from the other NPC's input, and that group context does not contain the full private memory. No hard-coded response may substitute for this evidence.

### 12.4 Acceptance decision

Current decision: NOT READY — implementation and live playthroughs have not been performed. Update only after recording actual outcomes. Demo 1 is accepted when all required checks pass in the exported Windows application and the owner is satisfied with visual coherence, character distinction, and comfort of alternating play and conversation. Any missing credentials, missing required animation, mock-only demonstration, or untested persistence remains visible as incomplete work. Later keepsakes, expansion, celebrations, gifts, local inference, and a larger world remain out of scope.

## 13. Technical References

- [Godot 4.7 stable](https://godotengine.org/download/archive/4.7-stable/)
- [Godot local data paths](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html)
- [Godot HTTPClient](https://docs.godotengine.org/en/stable/classes/class_httpclient.html)
- [FastAPI streaming responses](https://fastapi.tiangolo.com/advanced/custom-response/)
- [Terraria unit conversion](https://terraria.wiki.gg/wiki/Template%3AReal-life_size)
- [Terraria player dimensions](https://docs.tmodloader.net/docs/stable/class_player.html)


---

## Proposed Additions (Phase 2, April Gong — not part of the original spec)

> Everything above this line is Ryan Zhou's SPEC.md exactly as received at commit `6bb0698`. The items below are proposals only; they do not change any requirement above.

**P1. Documentation location.** Sections 2, 11 and 12 forbid a README and require setup/acceptance results inside this file. For course handoff, setup instructions, the code map and the per-item acceptance report (format of §12.2) live in `README.md`, and an assessment of the inherited work lives in `HANDOFF_REPORT.md`. Proposal: allow §11/§12 content to live in README.md and keep SPEC.md as the design contract.

**P2. Provider base URL.** Resolve §11.2's open question: `NAEVIA_PROVIDER_BASE_URL` includes the version prefix (e.g. `https://api.openai.com/v1`); the adapter appends only `/chat/completions`.

**P3. Memory validation on both sides.** §5.4 does not say who rejects invented sources. Proposal: the backend validates every proposal (returns HTTP 422 on rejection, 502 on provider failure) and the client re-checks character ID and revision before replacing its file.

**P4. Oversized memory.** Reject proposals whose combined entry text exceeds 3,000 characters, and cap single entries at 400 characters; the model (or mock) is responsible for consolidating before proposing.

**P5. Mock labeling.** Mock replies are prefixed `[mock]` so that mock output can never be mistaken for live evidence during acceptance.

**P6. Marker targets.** A `@to:` marker naming the speaker themself or a non-participant falls back to `player`, including in private conversations.

**P7. Runtime-built SpriteFrames and TileSet.** §3.3 step 2 asks for `SpriteFrames` resources built in Godot. The client instead builds them (and the TileSet) at startup from `client/data/visuals.json`, which `client/tools/sync_art.py` generates from `art/export/manifest.json`. This keeps one source of truth for frame layout, fps and anchors. Proposal: accept data-driven construction as satisfying §3.3 step 2.

**P8. Client launch options.** `-- --save-slot=<name>` selects `user://saves/<name>/` (supports §11.3's fresh-save testing without touching the real save) and `-- --backend-url=<url>` overrides `client/data/config.json` (needed when port 8000 is already taken).

**P9. Level as data.** The editable level (§3.3 step 3) is `client/data/level.json`: ordered rectangle fills per tile layer plus props. Terrain is cleared wherever a resource is defined so mined cells reveal the wall layer behind them.
