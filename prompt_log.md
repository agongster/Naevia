# Prompt Log: Naevia Phase 2

## Models & tools

- Claude Code (VS Code extension), model Claude Opus 5.5 (`claude-opus-5-5`)
- Python 3.12.9, FastAPI, pytest, on macOS

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

## Times the AI did something I didn't want

### A. Trimmed real dependencies out of the lock file

While writing `server/requirements.lock`, Claude ran `pip freeze` and filtered out `opentelemetry-api` and `Pygments`, assuming they were stray packages. Neither the spec nor I asked for that. The spec requires a lock file of "pinned, installable" dependencies. When it checked afterwards, `pip show` reported that **FastAPI requires `opentelemetry-api`** and **pytest requires `Pygments`**. A fresh install would still have pulled them in, but unpinned, which defeats the purpose of a lock file.

**What was done:** the lock file was regenerated from the full `pip freeze` (23 packages, nothing filtered) before it was committed. Lesson: don't hand-edit a lock file based on what a package name "looks like".

### B. A commit whose tests don't pass by themselves

Commit `69da584` ("validate memory proposals") includes endpoint tests in `test_memory.py`. Those tests import `app.main`, which only arrives two commits later in `e5ccfc2`. If you check out `69da584` alone, the suite fails. I asked for small commits, and the AI split the files by topic without checking that each commit runs on its own.

**What was done:** the history was left as is rather than rewritten, and the problem is documented here. The suite passes from `e5ccfc2` onward. Future commits should run `pytest` before each commit.

<!-- Add your own instances below: things you noticed and corrected yourself. -->
