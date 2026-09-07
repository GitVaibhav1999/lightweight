#!/usr/bin/env python3
"""Build data/exercises.json from hasaneyldrm/exercises-dataset.

- Downloads upstream data/exercises.json (17 MB, 10 languages) to a cache dir.
- Keeps English only, renames fields, derives loadType, collapses camera/gender variants.
- Writes data/exercises.json (app seed) and data/exercises.meta.json (filter vocab + counts).
Media (thumbs/GIFs) is NOT copied here: it is © Gym visual, see data/NOTICE.md.
"""
import json, re, sys, urllib.request, collections, pathlib

RAW = "https://raw.githubusercontent.com/hasaneyldrm/exercises-dataset/main/data/exercises.json"
ROOT = pathlib.Path(__file__).resolve().parent.parent
CACHE = ROOT / ".cache" / "exercises.upstream.json"
OUT = ROOT / "data" / "exercises.json"
META = ROOT / "data" / "exercises.meta.json"

VARIANT_RE = re.compile(r"\s*\((?:back|side|front) pov\)|\s*\((?:male|female)\)", re.I)

def load_type(rec):
    if rec["category"] == "cardio":
        return "time"
    if rec["equipment"] in ("body weight", "assisted"):
        return "bodyweight+reps"
    return "weight+reps"

def main():
    CACHE.parent.mkdir(exist_ok=True)
    if not CACHE.exists() or "--refresh" in sys.argv:
        print("downloading", RAW)
        urllib.request.urlretrieve(RAW, CACHE)
    src = json.load(open(CACHE))

    out, seen, collapsed = [], {}, 0
    for r in src:
        base = VARIANT_RE.sub("", r["name"]).strip()
        if base in seen:                      # same exercise, different camera / model
            seen[base]["variants"].append(r["id"])
            collapsed += 1
            continue
        rec = {
            "id": r["id"],
            "name": base,
            "bodyPart": r["category"],
            "target": r["target"],
            "equipment": r["equipment"],
            "secondary": r["secondary_muscles"],
            "loadType": load_type(r),
            "thumb": r["image"].split("/")[-1],   # 180x180 jpg in upstream images/
            "gif": r["gif_url"].split("/")[-1],   # 180x180 gif in upstream videos/
            "steps": r["instruction_steps"]["en"],
            "variants": [],
        }
        seen[base] = rec
        out.append(rec)

    out.sort(key=lambda e: e["name"])
    OUT.write_text(json.dumps(out, separators=(",", ":"), ensure_ascii=False))

    meta = {
        "source": "https://github.com/hasaneyldrm/exercises-dataset",
        "upstreamCount": len(src),
        "count": len(out),
        "collapsedVariants": collapsed,
        "attribution": "Media © Gym visual — https://gymvisual.com/",
        "targets": collections.Counter(e["target"] for e in out).most_common(),
        "bodyParts": collections.Counter(e["bodyPart"] for e in out).most_common(),
        "equipment": collections.Counter(e["equipment"] for e in out).most_common(),
        "loadTypes": collections.Counter(e["loadType"] for e in out).most_common(),
    }
    META.write_text(json.dumps(meta, indent=2, ensure_ascii=False))
    print(f"{len(src)} upstream -> {len(out)} exercises ({collapsed} variants collapsed), {OUT.stat().st_size//1024} KB")

if __name__ == "__main__":
    main()
