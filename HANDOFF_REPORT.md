# Handoff Report: Naevia (inherited from Ryan Zhou)

Reviewer: April Gong · Date: 2026-10-29 · Inherited revision: `6bb0698`

## What I received

- `SPEC.md`: about 500 lines, version 0.7, covering the whole Demo 1 design. That includes gameplay, bubble UI, the backend API, the memory model, persistence, milestones, a 26-item acceptance checklist, and setup instructions.
- `art/`: 35 runtime PNGs with `manifest.json`, previews, two reference images, a palette, and `validation-report.json`.
- No code. No Godot project, no backend, no tests. The spec says this plainly ("Do not claim they already exist"), so I wasn't misled.

## What is strong

**The art package is real and checks out.** I independently compared all 35 PNG headers against the manifest. Every width equals frame width times frame count, every height matches, and every file is RGBA. There are no unlisted files. The manifest records frame counts, fps, looping, and foot anchors, which is exactly what Godot `SpriteFrames` needs. Walk and mine animations are 4 frames, not just idle poses. `scene_direction_2x.png` is assembled from the actual runtime tiles, so it is a trustworthy target for the first level.

**The interface contracts are precise enough to build from.** The NDJSON event format, the memory snapshot schema, the revision rule (`base_revision + 1`), the processing cursor, and the "only cite sources you were given" rule were all specific enough to turn directly into tests. I built the backend without having to guess at any of these.

**The privacy model is thought through.** Each character hears only their own audience, private entries are withheld in group prompts, and `learned_from` keeps knowledge tied to whoever said it. That is a coherent design, and it is testable. Most of my backend tests come straight from these rules.

**The acceptance checklist is honest about itself.** It separates "file checks passed" from "works in game", and it forbids passing items in mock mode. Every check has an ID.

## What is weak or risky

**1. Scope compared to what was delivered.** Demo 1 needs a full Godot game (tiles, mining, furniture, bubbles, streaming HTTP client), a backend, an AI memory pipeline, group-turn coordination, and a Windows export. The handoff is a design document plus art. That is a reasonable split of labor, but nearly all of the engineering risk was passed on to me.

**2. The spec forbids the documents this assignment requires.** SPEC.md says "No README… is required" and "Do not delegate these instructions to a README". It also requires setup and acceptance results to be written into SPEC §11–12. The course requires a separate README with the acceptance report, and requires SPEC.md to stay unchanged. I followed the course. The acceptance report and run instructions live in README.md, SPEC.md is untouched, and the conflict is noted in the proposals section at the bottom of SPEC.md.

**3. Platform lock-in.** The spec requires Windows, Godot 4.7, and a live paid model for every acceptance check. I develop on macOS. That means I can't produce or test the Windows build myself, and with no API key all live-dependent items are BLOCKED. I also could not confirm from the spec that "Godot 4.7 stable" is the right version; the next developer should check that before installing.

**4. Verbosity and repetition.** The same warnings appear several times ("not a playable level", "do not claim acceptance", "do not remove a requirement"). The git history shows README.md, doc/PRD.md, doc/README.md, and doc/SPEC.md being added and then folded into SPEC.md on the same day. The result is complete but slow to read, and the important contracts are buried among the restated cautions. The contracts are in §5.2–5.4 and §6.1.

**5. Some responsibilities are ambiguous.**
- Who validates memory? §5.4 says "the client accepts it only if…" but also "Reject invented sources…" without naming who does the rejecting. I did both: the backend rejects with 422, and the client should recheck.
- What does the `@to:` marker do in private chat? If the model writes one, it would be meaningless there. My filter strips it and only accepts targets that are participants other than the speaker.
- Are oversized memories rejected, or consolidated? The spec says "reject oversized text" and also "consolidate during updates". I reject anything over the cap. The mock consolidates by dropping the oldest experiences before proposing.

**6. Missing inputs.** There is no font (by design, but a CJK-capable font with a redistributable license is non-trivial to find). There are no character profile JSONs; only the one-line starter defaults in §4.3 exist. The tiles are a limited straight-edge set, not an autotile. The spec notes all of this, but each is extra work.

**7. Provenance.** The art was produced with an image generator and normalized, with no layered source. Any new art (more furniture, for example) has to be matched by eye. Since there's no layered source, regenerating a variation of an existing sprite isn't possible.

## Overall

This is a high-quality *design* handoff with a verified art package and no implementation. I trust the art and the API/memory contracts. I'd treat the length of the spec, its Windows-only acceptance path, and its ban on supporting docs as obstacles to work around rather than requirements. In my judgment, the biggest risk to finishing Demo 1 is the Godot client, which has not been started and is most of the remaining work.
