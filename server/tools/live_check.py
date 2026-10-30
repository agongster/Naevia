"""Backend-only live check (SPEC 11.2): private replies with streaming timing, memory
updates through the validator, and three group conversations. Prints everything
for a person to judge. Talks to a running backend; never reads the API key.

    .venv/bin/python tools/live_check.py http://127.0.0.1:8000 ../client/data/characters [group]

Pass a third argument to run only the group trials. Makes about 10-15 model calls.
"""
import json, sys, time
import httpx

BASE = sys.argv[1]
PROFILES = sys.argv[2]
prof = {c: json.load(open(f"{PROFILES}/{c}.json")) for c in ("witch", "blacksmith")}
GROUP = ["player", "witch", "blacksmith"]


def empty(cid):
    return {"schema_version": 1, "character_id": cid, "revision": 0, "last_processed_event_id": None,
            "facts": [], "ongoing": [], "experiences": []}


def ev(eid, speaker, text, audience, addressee="player"):
    return {"event_id": eid, "speaker": speaker, "addressee": addressee, "audience": audience, "text": text}


def chat(speaker, participants, memory, recent, scene):
    body = {"request_id": f"r{time.time_ns()}", "conversation_id": "live", "speaker_id": speaker,
            "participants": participants, "profile": prof[speaker], "memory": memory,
            "recent_messages": recent, "scene_context": scene}
    t0 = time.time(); first = None; deltas = 0; text = ""; done = None
    with httpx.stream("POST", f"{BASE}/v1/chat", json=body, timeout=90) as r:
        assert r.status_code == 200, r.status_code
        for line in r.iter_lines():
            if not line.strip():
                continue
            e = json.loads(line)
            if e["type"] == "text_delta":
                first = first or time.time() - t0
                deltas += 1
                text += e["text"]
            elif e["type"] == "done":
                done = e
            else:
                print("  ERROR EVENT:", e.get("message")); return None, None
    total = time.time() - t0
    print(f"  [{speaker} -> {done['addressee']}] {deltas} deltas, first after {first:.2f}s, done after {total:.2f}s")
    print(f"  \"{text.strip()}\"")
    return text.strip(), done["addressee"]


def update(cid, memory, events):
    body = {"request_id": f"m{time.time_ns()}", "character_id": cid, "base_revision": memory["revision"],
            "memory": memory, "new_events": events}
    r = httpx.post(f"{BASE}/v1/memory/update", json=body, timeout=90)
    print(f"  memory update for {cid}: HTTP {r.status_code}")
    if r.status_code != 200:
        print("  ", r.json().get("detail")); return memory
    m = r.json()["memory"]
    for s in ("facts", "ongoing", "experiences"):
        for e in m[s]:
            print(f"    {s:11} {e['share_scope']:7} from {e['learned_from']:10} {e['text']}")
    return m


private_w = ["player", "witch"]
GROUP_ONLY = len(sys.argv) > 3
wm = empty("witch")
if not GROUP_ONLY:
    print("1. Private: witch (via pigeon)")
    p1 = "My statistics exam is on Thursday and I'm honestly pretty nervous about it."
    w1, _ = chat("witch", private_w, empty("witch"), [ev("e1", "player", p1, private_w, "witch")],
                 "The witch is at home in her garden. The player's words reach her by messenger pigeon.")

    print("\n2. Private: blacksmith")
    private_b = ["player", "blacksmith"]
    b1, _ = chat("blacksmith", private_b, empty("blacksmith"),
                 [ev("b1", "player", "Hey! What have you been working on lately?", private_b, "blacksmith")],
                 "The blacksmith has dropped by and is standing at the player's front door.")

    print("\n3. Memory update (witch) through the backend validator")
    wm = update("witch", empty("witch"), [ev("e1", "player", p1, private_w, "witch"), ev("e2", "witch", w1, private_w)])

    print("\n4. Later private message: does the witch use the remembered detail?")
    w2, _ = chat("witch", private_w, wm, [ev("e3", "player", "Any idea what I should do the night before?", private_w, "witch")],
                 "The witch is at home in her garden. The player's words reach her by messenger pigeon.")

print("\n5. Group: announcement to everyone; every character gets a turn (may decline), @to: handoffs, max 3")
scene = "The witch and the blacksmith are visiting the player's house together. All three can hear each other."
mems = {"witch": wm, "blacksmith": empty("blacksmith")}
for trial, (announce, first) in enumerate([("Guess what, I made the Dean's List!", "witch"),
                                           ("I'm thinking of planting a herb garden this spring.", "blacksmith"),
                                           ("Do either of you have plans for the weekend?", "witch")]):
    print(f"  -- trial {trial + 1}: player to all: {announce!r}")
    hist = [ev("g1", "player", announce, GROUP, "all")]
    speaker, spoken = first, set()
    for turn in range(3):
        shared = dict(mems[speaker]); shared.update({s: [e for e in mems[speaker][s] if e["share_scope"] == "shared"]
                                                     for s in ("facts", "ongoing", "experiences")})
        text, to = chat(speaker, GROUP, shared, hist, scene)
        if text is None:
            break
        spoken.add(speaker)
        if text.strip(".… ") != "":
            hist.append(ev(f"g{len(hist) + 1}", speaker, text, GROUP, to))
        if to in ("witch", "blacksmith") and to != speaker:
            speaker = to
        else:
            unheard = [c for c in ("witch", "blacksmith") if c not in spoken]
            if not unheard:
                break
            speaker = unheard[0]

print("\n6. Memory update (blacksmith) from the group events he heard")
update("blacksmith", empty("blacksmith"), hist)
