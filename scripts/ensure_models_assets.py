#!/usr/bin/env python3
import hashlib
import json
import shutil
import subprocess
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
    with urllib.request.urlopen(url) as r, out_path.open("wb") as f:
        f.write(r.read())


def main():
    if not MANIFEST_PATH.exists():
        raise SystemExit(f"Missing manifest: {MANIFEST_PATH}")
    data = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    models = data.get("models", [])
    if not models:
        raise SystemExit("No models defined in manifest.")

    for m in models:
        name = m["name"]
        file_name = m["file_name"]
        url = m["url"]
        expected = (m.get("sha256") or "").strip().lower()
        target = MODELS_DIR / file_name

        needs_download = not target.exists()
        if not needs_download and expected:
            actual = sha256_file(target)
            needs_download = actual != expected

        if needs_download:
            print(f"[models] downloading {name} -> {target}")
            download(url, target)
        else:
            print(f"[models] cached {name}")

        if expected:
            actual = sha256_file(target)
            if actual != expected:
                raise SystemExit(f"Checksum mismatch for {name}: {target}")

    print("[models] assets/models ensured")


if __name__ == "__main__":
    main()

