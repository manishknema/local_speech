#!/usr/bin/env python3
"""
compute_wer.py — Offline ASR quality benchmark for VigyanTranscribe.

Runs meetsync_smoke.dart on all speech fixtures (clean + noisy variants),
computes Word Error Rate (WER) against reference transcripts, and produces
a structured JSON report.

Usage:
  python scripts/compute_wer.py
  python scripts/compute_wer.py --report wer_report.json
  python scripts/compute_wer.py --fixture hi_clean --fixture en_clean

Requirements:
  - assets/models/indic_conformer/model.int8.onnx  (downloaded via ensure_models_assets.py --full)
  - assets/models/indic_conformer/tokens.txt
  - test_fixtures/wav16k/*.wav  (prepared via prepare_test_fixtures.py)
  - test_fixtures/references/*.txt  (one file per fixture id, e.g. hi_clean.txt)
  - dart run tool/meetsync_smoke.dart available

WER = (S + I + D) / N  where:
  S = substitutions, I = insertions, D = deletions, N = reference word count
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).parent.parent
MANIFEST_PATH = REPO_ROOT / "test_fixtures" / "fixtures_manifest.json"
REFERENCES_DIR = REPO_ROOT / "test_fixtures" / "references"
WAV16K_DIR = REPO_ROOT / "test_fixtures" / "wav16k"
NOISY_DIR = REPO_ROOT / "test_fixtures" / "noisy_variants"
MODEL_PATH = REPO_ROOT / "assets" / "models" / "indic_conformer" / "model.int8.onnx"
TOKENS_PATH = REPO_ROOT / "assets" / "models" / "indic_conformer" / "tokens.txt"

# SNR tiers used for noisy variant naming
NOISY_TIERS = [
    "snr_plus30dB", "snr_plus20dB", "snr_plus15dB", "snr_plus10dB",
    "snr_plus5dB", "snr_plus0dB", "snr_minus5dB", "snr_minus10dB",
]
NOISE_SOURCES = ["noise_fan", "music_bg"]


def levenshtein_words(ref: list[str], hyp: list[str]) -> tuple[int, int, int]:
    """Return (substitutions, insertions, deletions) between ref and hyp word lists."""
    n, m = len(ref), len(hyp)
    # dp[i][j] = min edit distance between ref[:i] and hyp[:j]
    dp = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n + 1):
        dp[i][0] = i
    for j in range(m + 1):
        dp[0][j] = j
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            if ref[i - 1] == hyp[j - 1]:
                dp[i][j] = dp[i - 1][j - 1]
            else:
                dp[i][j] = 1 + min(dp[i - 1][j - 1], dp[i - 1][j], dp[i][j - 1])

    # Back-trace to count S/I/D
    i, j = n, m
    s = i_count = d = 0
    while i > 0 or j > 0:
        if i > 0 and j > 0 and ref[i - 1] == hyp[j - 1]:
            i -= 1
            j -= 1
        elif i > 0 and j > 0 and dp[i][j] == dp[i - 1][j - 1] + 1:
            s += 1
            i -= 1
            j -= 1
        elif j > 0 and dp[i][j] == dp[i][j - 1] + 1:
            i_count += 1
            j -= 1
        else:
            d += 1
            i -= 1
    return s, i_count, d


def normalize_text(text: str) -> list[str]:
    """Lowercase, strip punctuation, return word tokens."""
    text = text.lower()
    text = re.sub(r"[^\w\s\u0900-\u097f\u0c00-\u0c7f\u0b80-\u0bff\u0980-\u09ff]", " ", text)
    return text.split()


def compute_wer(ref_words: list[str], hyp_words: list[str]) -> dict:
    if not ref_words:
        return {"wer": None, "note": "empty_reference"}
    s, ins, d = levenshtein_words(ref_words, hyp_words)
    total = len(ref_words)
    wer = (s + ins + d) / total
    return {
        "wer": round(wer, 4),
        "wer_pct": round(wer * 100, 2),
        "substitutions": s,
        "insertions": ins,
        "deletions": d,
        "ref_words": total,
        "hyp_words": len(hyp_words),
    }


def run_asr(wav_path: Path) -> str | None:
    """Run meetsync_smoke.dart on a WAV file and return the transcript text."""
    cmd = [
        "dart", "run", "tool/meetsync_smoke.dart",
        str(MODEL_PATH),
        str(TOKENS_PATH),
        str(wav_path),
    ]
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            cwd=str(REPO_ROOT),
            timeout=120,
        )
        if result.returncode != 0:
            print(f"  [ASR ERROR] {wav_path.name}: {result.stderr.strip()[:200]}", file=sys.stderr)
            return None
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        print(f"  [ASR TIMEOUT] {wav_path.name}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"  [ASR EXCEPTION] {wav_path.name}: {e}", file=sys.stderr)
        return None


def load_reference(fixture_id: str) -> str | None:
    ref_path = REFERENCES_DIR / f"{fixture_id}.txt"
    if ref_path.exists():
        return ref_path.read_text(encoding="utf-8").strip()
    return None


def main():
    parser = argparse.ArgumentParser(description="Compute WER for ASR fixtures.")
    parser.add_argument("--report", default=None, help="Path to write JSON report")
    parser.add_argument("--fixture", action="append", default=[], help="Run only these fixture IDs")
    parser.add_argument(
        "--noisy",
        action="store_true",
        default=False,
        help="Also benchmark noisy variants (adds many ASR runs)",
    )
    args = parser.parse_args()

    # Validate prerequisites
    if not MODEL_PATH.exists():
        raise SystemExit(
            f"IndicConformer model not found: {MODEL_PATH}\n"
            "Run: python scripts/ensure_models_assets.py --full"
        )
    if not TOKENS_PATH.exists():
        raise SystemExit(f"Tokens file not found: {TOKENS_PATH}")
    if not MANIFEST_PATH.exists():
        raise SystemExit(f"Fixtures manifest not found: {MANIFEST_PATH}")

    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    fixtures = manifest.get("fixtures", [])
    speech_fixtures = [
        f for f in fixtures
        if f.get("category", "").startswith("speech")
    ]

    if args.fixture:
        speech_fixtures = [f for f in speech_fixtures if f["id"] in args.fixture]
        if not speech_fixtures:
            raise SystemExit(f"No matching fixtures for: {args.fixture}")

    report = {
        "model": "indic_conformer_int8",
        "date": "2026-05-27",
        "fixtures": [],
        "summary": {},
    }

    all_wers = []
    per_lang_wers: dict[str, list[float]] = {}

    for fixture in speech_fixtures:
        fid = fixture["id"]
        lang = fixture.get("category", "unknown").replace("speech_", "")
        wav_path = REPO_ROOT / fixture["path"]

        ref_text = load_reference(fid)
        has_ref = ref_text is not None and len(ref_text.strip()) > 0

        print(f"\n[WER] {fid} (lang={lang})")

        fixture_result = {
            "id": fid,
            "language": lang,
            "has_reference": has_ref,
            "clean": None,
            "noisy_variants": [],
        }

        # ── Clean fixture ──────────────────────────────────────
        if wav_path.exists():
            hyp = run_asr(wav_path)
            if hyp is not None:
                print(f"  hyp: {hyp[:120]}")
                if has_ref:
                    ref_words = normalize_text(ref_text)
                    hyp_words = normalize_text(hyp)
                    metrics = compute_wer(ref_words, hyp_words)
                    print(f"  WER: {metrics['wer_pct']}%  (S={metrics['substitutions']} I={metrics['insertions']} D={metrics['deletions']})")
                    all_wers.append(metrics["wer"])
                    per_lang_wers.setdefault(lang, []).append(metrics["wer"])
                    fixture_result["clean"] = {"transcript": hyp, **metrics}
                else:
                    fixture_result["clean"] = {"transcript": hyp, "wer": None, "note": "no_reference_transcript"}
                    print("  (no reference — transcript captured, WER not computed)")
        else:
            print(f"  [SKIP] WAV not found: {wav_path}")

        # ── Noisy variants ─────────────────────────────────────
        if args.noisy:
            for noise_src in NOISE_SOURCES:
                for tier in NOISY_TIERS:
                    noisy_name = f"{fid}__{noise_src}__{tier}.wav"
                    noisy_path = NOISY_DIR / noisy_name
                    if not noisy_path.exists():
                        continue
                    hyp = run_asr(noisy_path)
                    variant_result = {"wav": noisy_name, "noise": noise_src, "snr": tier}
                    if hyp is not None and has_ref:
                        ref_words = normalize_text(ref_text)
                        hyp_words = normalize_text(hyp)
                        metrics = compute_wer(ref_words, hyp_words)
                        print(f"  {tier} ({noise_src}): WER {metrics['wer_pct']}%")
                        variant_result.update({"transcript": hyp, **metrics})
                        all_wers.append(metrics["wer"])
                        per_lang_wers.setdefault(lang, []).append(metrics["wer"])
                    elif hyp is not None:
                        variant_result["transcript"] = hyp
                    fixture_result["noisy_variants"].append(variant_result)

        report["fixtures"].append(fixture_result)

    # ── Summary ───────────────────────────────────────────────
    if all_wers:
        report["summary"]["overall_wer_pct"] = round(
            sum(all_wers) / len(all_wers) * 100, 2
        )
    for lang, wers in per_lang_wers.items():
        report["summary"][f"wer_{lang}_pct"] = round(sum(wers) / len(wers) * 100, 2)

    print("\n─── WER Summary ─────────────────────────────────────")
    for k, v in report["summary"].items():
        print(f"  {k}: {v}%")

    if args.report:
        Path(args.report).write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
        print(f"\n[WER] Report written to: {args.report}")
    else:
        print("\n[WER] (pass --report <path> to save JSON report)")


if __name__ == "__main__":
    main()
