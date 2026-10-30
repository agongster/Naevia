# Prompt Log: Naevia Phase 2

## Models & tools

- Claude Code (VS Code extension), model Claude Opus 5.5 (`claude-opus-5-5`)
- Python 3.12.9, FastAPI, pytest, on macOS
- Godot 4.7.2 stable (Compatibility renderer), on an Apple M2 Mac

## Prompts (verbatim)

### 1. 2026-10-29

> please make sure you read over and understand the spec for Naevia. Also, here are the instructions for what I need in the end:
>
> The initial commit must be the other student's unmodified work, committed before you change anything (see Phase 2 Step 0). This is the easiest thing here to forget and the most annoying to fix later.
> Your subsequent commits, ideally several small ones rather than one large one
> Their SPEC.md, kept as you received it. Put any additions you want to propose in a clearly marked section at the bottom rather than editing theirs.
> An updated README.md containing your acceptance criteria report, plus run instructions and code map, revised so the next person could take over from you
> HANDOFF_REPORT.md, your honest review of what you inherited
> prompt_log.md for Phase 2, including at least one instance of your AI tool doing something you didn't want, and what you did about it
> Credit the original author by name at the top of the README. They designed the game and built the foundation.
> These are all separate files. The spec, the README, the handoff report, and the prompt log each have a different audience and a different job. Don't merge them, and don't paste one into the bottom of another.
>
> start on whatever is missing.

**Outcome:** Claude read SPEC.md and checked that the repo already began with Ryan's 7 unmodified commits (tree clean, latest `6bb0698`), so Step 0 was already satisfied. It re-validated all 35 art PNGs against the manifest, with 0 mismatches. Then it built the FastAPI backend (`server/`), with 33 passing pytest tests, as 4 small commits. It wrote README.md, HANDOFF_REPORT.md, this log, and a proposals section at the bottom of SPEC.md. It did not start the Godot client, because Godot isn't installed on this machine.

### 2. 2026-10-29

> please make sure that 75% of the original work is maintained. that said, it seems like because there's no code, there's not much to modify in the first place? and i should just be going off of the art and other references? the 75% is referring more to restructuring code and whatnot.

**Outcome:** Claude compared the repo with Ryan's last commit (`6bb0698`) using git diff and confirmed that 100% of his work is unchanged. All 55 of his files are intact. The art has no changes. SPEC.md has 0 lines removed and only the appended proposals section. All 20 changed files are additions (1,083 lines). Claude agreed that, with no inherited code, the 75% rule means keeping the spec's design and the art package as the foundation, rather than restructuring them.

### 3. 2026-10-29

> Since I am not on Windows, nor do I have Godot, how do you recommend developing this game?

**Outcome:** Claude recommended installing Godot on macOS and building and testing there against the mock backend. Godot can export the Windows `.exe` from the Mac, so a Windows machine is needed only for the final acceptance run, for example a campus Windows lab. Claude advised against switching to a web or Python engine, because the spec rules out a web page and the switch would discard Ryan's chosen engine. If Windows access is impossible, the plan is to mark those checks BLOCKED and propose the change in the SPEC proposals section.

### 4. 2026-10-29

> i just installed godot, please start on the game. start by implementing a playable demo with the core mechanics and using the art that he has in the repo.

**Outcome:** Claude built the Godot 4.7.2 client (`client/`) as milestone A from SPEC §8:
- **Art:** Ryan's 35 PNGs are copied unchanged by `tools/sync_art.py`, which also generates `visuals.json` from his manifest.
- **Scenes:** `World.tscn` laid out as in SPEC §3.1.
- **Mechanics:** movement and jumping, hold-to-mine with crack frames and stone chips, bag with buy/place/arrange/store, and pigeon and blacksmith visits with click targets.
- **Chat:** streamed mock replies in anchored, segmented bubbles styled after Ryan's `ui_direction.png`, a failure bubble with Retry, a History panel, and atomic JSON saves plus JSONL history.

Claude also wrote `tests/smoke_test.gd`, which plays the real scene with simulated input and saves screenshots. It passes 43 checks, and Claude looked at the screenshots to confirm layout and alignment. Memory (C), group chat (D) and the Windows export (E) are not started. The README acceptance report was updated: 0/26 PASS, with mock evidence for 11 checks.

### 5. 2026-10-29

> how do i run this

**Outcome:** Claude gave step-by-step terminal commands from the README: start the mock backend, then launch the game with `godot --path client`. Port 8000 was still taken by another project's server (`tally-backend`), so it suggested running the backend on port 8010 and passing `--backend-url`. No code changed.

### 6. 2026-10-29

> do i need to give you an openai api key?

**Outcome:** Claude said no. Mock mode needs no key, and the key should never be pasted into the chat. It belongs only in the local, git-ignored `server/.env`. A key (OpenAI or any OpenAI-compatible provider) is only needed for the spec's live-AI acceptance checks. Without one, those checks stay BLOCKED. No code changed.

### 7. 2026-10-29

> ok move to the next phase of the game. what is to be implemented next?

**Outcome:** Claude said the next phase is milestone C from SPEC §8 (local memory), then built it:
- **`MemoryStore` autoload** (`client/scripts/memory_store.gd`): keeps `characters/<id>.memory.json` and sends the events each character heard to `/v1/memory/update` after every completed exchange. It re-checks the proposal on the client (character, request, revision = base + 1, cursor, cited sources, scopes, size caps) and replaces the file atomically. Updates are serialized per character. Failures keep the old file and retry after 20 s, and pending work resumes on launch.
- **Conversation:** sends the real memory, and waits for an in-progress update before asking for a reply.
- **History panel:** a Memory view showing each character's current memory.
- **Mock backend:** replies quote one memory entry ("I remember: …") so memory is visible without an API key (1 new pytest test, 34 total).
- **Smoke test:** 43 → 64 checks. It covers proposal rejection, isolation between the two characters, a failed update that keeps the old snapshot, resuming pending work after a restart, and the witch recalling the exams after a restart.

README status, code map and acceptance notes were updated (still 0/26 PASS; mock evidence for 14 checks).

## Times the AI did something I didn't want

### A. Trimmed real dependencies out of the lock file

While writing `server/requirements.lock`, Claude ran `pip freeze` and filtered out `opentelemetry-api` and `Pygments`, assuming they were stray packages. Neither the spec nor I asked for that. The spec requires a lock file of "pinned, installable" dependencies. When it checked afterwards, `pip show` reported that **FastAPI requires `opentelemetry-api`** and **pytest requires `Pygments`**. A fresh install would still have pulled them in, but unpinned, which defeats the purpose of a lock file.

**What was done:** the lock file was regenerated from the full `pip freeze` (23 packages, nothing filtered) before it was committed. Lesson: don't hand-edit a lock file based on what a package name "looks like".

### B. A commit whose tests don't pass by themselves

Commit `69da584` ("validate memory proposals") includes endpoint tests in `test_memory.py`. Those tests import `app.main`, which only arrives two commits later in `e5ccfc2`. If you check out `69da584` alone, the suite fails. I asked for small commits, and the AI split the files by topic without checking that each commit runs on its own.

**What was done:** the history was left as is rather than rewritten, and the problem is documented here. The suite passes from `e5ccfc2` onward. Future commits should run `pytest` before each commit.

### C. Wrote characters that could never be clicked

In `Npc.tscn` and `Pigeon.tscn`, Claude set the click areas to `collision_layer = 0`, meaning to keep them out of the physics simulation. Godot's mouse picking only finds objects on at least one layer, so the pigeon and blacksmith silently ignored every click. Nothing errored; the feature just didn't work. If it had only been tested by reading the code, this would have shipped.

**What was done:** the smoke test failed on "pigeon opens witch conversation". Claude checked a screenshot, saw the pigeon was exactly where the click landed, found the layer setting, and moved the click areas to their own layer 2, which nothing collides with. Lesson: test interactive features by actually clicking them.

### D. Other first-draft bugs the smoke test caught

These are smaller mistakes from the same session. All were caught before committing.
- **Overrode a built-in method.** A helper was named `_get`, which accidentally overrides Godot's built-in `Object._get` property hook.
- **Initialization order.** The HUD and contact scheduler used World's node references before World had set them, because in Godot children are ready before their parent.
- **Oversized error bubble.** The error bubble stayed about 270 px tall because its size was computed before the wrapped text settled.
- **Test fooled by the real cursor and by throttling.** The first test version read the real mouse cursor and depended on real-time frame rates, so it failed at random when the window was behind VS Code. That was fixed with event-based pointer tracking, mouse passthrough, and `--fixed-fps 60`.

The AI also found that port 8000 was already in use by another program on this Mac (PID 87866). It did **not** kill that process; it ran the test backend on port 8010 and added a `--backend-url` option instead.

### E. Said the test backend was stopped when it wasn't

At the end of prompt 4, Claude reported that it had stopped the test backend on port 8010. It hadn't: the old process was still running. In this session the new backend failed to start ("address already in use"), and Claude didn't notice because the startup output went to a log file. The smoke test then talked to the **old** backend code, and "witch reply draws on her saved memory" failed for a reason that had nothing to do with the new memory code.

**What was done:** Claude checked which process held port 8010, confirmed from its command line and working directory that it was the Naevia backend it had started (not one of my other projects), stopped it, and restarted the current code. Lesson: after starting a server, check that it actually bound the port, and after stopping one, check that it's gone.

### F. A History panel bug that shipped in the demo

In the milestone A demo, the History panel opened partly off-screen in the bottom-right corner. Claude had reviewed the demo screenshots, but none of them showed the History panel open, so the bug went unnoticed. It only surfaced when a new screenshot of the Memory view showed the panel cut off.

**What was done:** the panel is now a fixed 400 × 240 box centered on the screen, and the smoke test takes a screenshot of it open. Lesson: "I looked at the screenshots" only covers what the screenshots show.

### G. Blamed flaky test runs on the wrong cause

Smoke-test runs started failing at random in the mining section. Claude's first guess, that the window wasn't focused when the test started, was wrong: the fix for it changed nothing. Claude then logged focus changes and found that macOS takes focus away from the test window about 3 seconds into **every** run, and Godot releases held mouse buttons when that happens.

**What was done:** the test now takes focus back when it loses it, and it holds the mouse on each stone until the tile breaks, re-pressing if the button was released. It then passed 6 of 6 runs back to back. The game's behavior (letting go of held buttons when you switch apps) was left as is, because that's correct for players.

<!-- Add your own instances below: things you noticed and corrected yourself. -->
