#!/usr/bin/env python3
import argparse
import math
import shutil
import subprocess
from pathlib import Path


SNR_LEVELS_DB = [30, 20, 15, 10, 5, 0, -5, -10]


def run(cmd):
    print(">>", " ".join(cmd))
    subprocess.run(cmd, check=True)


def ensure_tool(name):
    if shutil.which(name) is None:
        raise RuntimeError(f"Required tool not found on PATH: {name}")


def gain_for_snr_db(snr_db: int) -> float:
    return math.pow(10.0, -snr_db / 20.0)


def snr_label(snr_db: int) -> str:
    sign = "plus" if snr_db >= 0 else "minus"
    return f"{sign}{abs(snr_db)}dB"


def main():
    parser = argparse.ArgumentParser(description="Generate noisy SNR variants for speech fixtures.")
    parser.add_argument("--base-dir", default="test_fixtures/wav16k")
    parser.add_argument("--out-dir", default="test_fixtures/noisy_variants")
    args = parser.parse_args()

    ensure_tool("ffmpeg")

    base_dir = Path(args.base_dir)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    speech_files = [
        base_dir / "en_clean.wav",
        base_dir / "hi_clean.wav",
        base_dir / "code_switch_en_hi.wav",
    ]
    noise_files = [
        base_dir / "noise_fan.wav",
        base_dir / "music_bg.wav",
    ]

    for f in speech_files + noise_files:
        if not f.exists():
            raise FileNotFoundError(f"Missing fixture: {f}")

    for speech in speech_files:
        speech_id = speech.stem
        for noise in noise_files:
            noise_id = noise.stem
            for snr in SNR_LEVELS_DB:
                gain = gain_for_snr_db(snr)
                out_name = f"{speech_id}__{noise_id}__snr_{snr_label(snr)}.wav"
                out_path = out_dir / out_name
                run([
                    "ffmpeg",
                    "-y",
                    "-i",
                    str(speech),
                    "-stream_loop",
                    "-1",
                    "-i",
                    str(noise),
                    "-filter_complex",
                    f"[1:a]volume={gain:.8f}[n];[0:a][n]amix=inputs=2:duration=first:dropout_transition=0[m]",
                    "-map",
                    "[m]",
                    "-ac",
                    "1",
                    "-ar",
                    "16000",
                    "-sample_fmt",
                    "s16",
                    str(out_path),
                ])

    print("Noisy variant generation complete.")


if __name__ == "__main__":
    main()

