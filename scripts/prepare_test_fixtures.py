#!/usr/bin/env python3
import argparse
import json
import shutil
import subprocess
from pathlib import Path


def run(cmd):
    print(">>", " ".join(cmd))
    subprocess.run(cmd, check=True)


def ensure_tool(name):
    if shutil.which(name) is None:
        raise RuntimeError(f"Required tool not found on PATH: {name}")


def main():
    parser = argparse.ArgumentParser(description="Prepare canonical audio fixtures for VAD/LID tests.")
    parser.add_argument("--config", default="test_fixtures/sources.json")
    parser.add_argument("--raw-dir", default="test_fixtures/raw")
    parser.add_argument("--out-dir", default="test_fixtures/wav16k")
    parser.add_argument("--skip-download", action="store_true")
    parser.add_argument("--skip-convert", action="store_true")
    args = parser.parse_args()

    ensure_tool("ffmpeg")
    if not args.skip_download:
        ensure_tool("yt-dlp")

    config_path = Path(args.config)
    raw_dir = Path(args.raw_dir)
    out_dir = Path(args.out_dir)
    raw_dir.mkdir(parents=True, exist_ok=True)
    out_dir.mkdir(parents=True, exist_ok=True)

    cfg = json.loads(config_path.read_text(encoding="utf-8"))
    defaults = cfg["defaults"]
    duration = str(defaults["duration_seconds"])
    sample_rate = str(defaults["sample_rate_hz"])
    channels = str(defaults["channels"])
    sample_fmt = defaults["sample_fmt"]

    for item in cfg["sources"]:
        raw_path = raw_dir / item["raw_file"]
        out_path = out_dir / item["out_file"]
        url = f"https://www.youtube.com/watch?v={item['youtube_id']}"

        if not args.skip_download:
            run([
                "yt-dlp",
                url,
                "-f",
                "bestaudio[ext=m4a]/bestaudio",
                "--no-playlist",
                "-o",
                str(raw_path),
            ])

        if not args.skip_convert:
            run([
                "ffmpeg",
                "-y",
                "-ss",
                item["start"],
                "-t",
                duration,
                "-i",
                str(raw_path),
                "-ac",
                channels,
                "-ar",
                sample_rate,
                "-sample_fmt",
                sample_fmt,
                str(out_path),
            ])

    # Always regenerate synthetic silence for baseline checks.
    run([
        "ffmpeg",
        "-y",
        "-f",
        "lavfi",
        "-i",
        f"anullsrc=r={sample_rate}:cl=mono",
        "-t",
        duration,
        "-ac",
        channels,
        "-ar",
        sample_rate,
        "-sample_fmt",
        sample_fmt,
        str(out_dir / "silence.wav"),
    ])

    print("Fixture preparation complete.")


if __name__ == "__main__":
    main()

