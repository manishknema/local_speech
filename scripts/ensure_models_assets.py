#!/usr/bin/env python3
"""
ensure_models_assets.py — Download and verify models listed in assets/models/models_manifest.json.

Usage:
  python scripts/ensure_models_assets.py           # skip large models (ci_skip=true)
  python scripts/ensure_models_assets.py --full    # download all models including large ones
  python scripts/ensure_models_assets.py --ci      # alias for default (skip ci_skip=true)

Models with a "subdir" field are placed in assets/models/<subdir>/<file_name>.
Models with ci_skip=true are skipped unless --full is passed.
"""
import argparse
import hashlib
import json
import urllib.request
from pathlib import Path


MANIFEST_PATH = Path("assets/models/models_manifest.json")
MODELS_DIR = Path("assets/models")


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            chunk = f.read(1024 * 1024)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def download(url: str, out_path: Path):
    out_path.parent.mkdir(parents=True, exist_ok=True)
    print(f"  -> GET {url}")
    with urllib.request.urlopen(url) as r, out_path.open("wb") as f:
        downloaded = 0
        while True:
            chunk = r.read(1024 * 1024)
            if not chunk:
                break
            f.write(chunk)
            downloaded += len(chunk)
            print(f"\r  {downloaded // (1024*1024)} MB", end="", flush=True)
    print()


def main():
    parser = argparse.ArgumentParser(description="Ensure model assets are present and verified.")
    parser.add_argument(
        "--full",
        action="store_true",
        help="Download all models including large ones (ci_skip=true)",
    )
    parser.add_argument(
        "--ci",
        action="store_true",
        help="CI mode — skip large models (same as default, explicit alias)",
    )
    args = parser.parse_args()
    download_all = args.full

    if not MANIFEST_PATH.exists():
        raise SystemExit(f"Missing manifest: {MANIFEST_PATH}")
    data = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    models = data.get("models", [])
    if not models:
        raise SystemExit("No models defined in manifest.")

    skipped = []
    for m in models:
        name = m["name"]
        file_name = m["file_name"]
        url = m.get("url", "")
        expected = (m.get("sha256") or "").strip().lower()
        ci_skip = m.get("ci_skip", False)
        subdir = m.get("subdir", "")
        size_mb = m.get("size_mb", 0)

        if subdir:
            target = MODELS_DIR / subdir / file_name
        else:
            target = MODELS_DIR / file_name

        # Skip large models in default/CI mode
        if ci_skip and not download_all:
            if target.exists():
                print(f"[models] present (large) {name}")
            else:
                skipped.append(f"{name} (~{size_mb}MB) — run with --full to download")
            continue

        needs_download = not target.exists()
        if not needs_download and expected:
            actual = sha256_file(target)
            needs_download = actual != expected

        if needs_download:
            if not url:
                raise SystemExit(f"No URL for {name} and file is missing: {target}")
            print(f"[models] downloading {name} ({size_mb}MB) -> {target}")
            download(url, target)
        else:
            print(f"[models] cached {name}")

        if expected:
            actual = sha256_file(target)
            if actual != expected:
                raise SystemExit(f"Checksum mismatch for {name}: {target}")

    print("[models] assets/models ensured")

    if skipped:
        print("\n[models] SKIPPED (large models — run with --full to download):")
        for s in skipped:
            print(f"  - {s}")


if __name__ == "__main__":
    main()
