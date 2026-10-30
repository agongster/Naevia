"""Copy runtime PNGs from art/export into client/assets and build data/visuals.json.

Run from the repo root:  python3 client/tools/sync_art.py
Visual IDs are the stable IDs from art/export/manifest.json (SPEC 3.3, step 4).
"""

import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXPORT = ROOT / "art" / "export"
ASSETS = ROOT / "client" / "assets"
VISUALS = ROOT / "client" / "data" / "visuals.json"


def main() -> None:
    manifest = json.loads((EXPORT / "manifest.json").read_text())
    visuals = {}
    for asset in manifest["assets"]:
        src = EXPORT / asset["path"]
        dst = ASSETS / asset["path"]
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
        visuals[asset["id"]] = {
            "path": f"res://assets/{asset['path']}",
            "source": f"art/export/{asset['path']}",
            "frame_width": asset["frame_width"],
            "frame_height": asset["frame_height"],
            "frame_count": asset["frame_count"],
            "fps": asset["fps"],
            "loop": asset["loop"],
            "anchor": asset.get("anchor_px", [0, 0]),
        }
    VISUALS.write_text(json.dumps(visuals, indent=2) + "\n")
    print(f"synced {len(visuals)} assets")


if __name__ == "__main__":
    main()
