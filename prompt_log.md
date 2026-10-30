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

<!-- Add your own instances below: things you noticed and corrected yourself. -->
