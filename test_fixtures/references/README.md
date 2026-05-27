# WER Reference Transcripts

One `.txt` file per fixture ID. Used by `scripts/compute_wer.py` to compute Word Error Rate.

## How to populate

1. Play each WAV: `test_fixtures/wav16k/<id>.wav`
2. Transcribe manually (or use a reference system)
3. Save clean lowercased text to `test_fixtures/references/<id>.txt`
4. Run: `python scripts/compute_wer.py`

## Naming convention

File name = fixture ID from `test_fixtures/fixtures_manifest.json` + `.txt`

| File | Language | Source clip |
|------|----------|-------------|
| `en_clean.txt` | English | YouTube (ce5qg_rDyRo) |
| `hi_clean.txt` | Hindi | YouTube (oaBV9BSvv98) |
| `code_switch_en_hi.txt` | EN+HI code-switch | YouTube (7uRyqg2NT-k) |

## Quality gate

WER targets (IndicConformer INT8, clean speech):
- Hindi clean: WER < 20%
- English clean: WER < 15% (note: IndicConformer is Indic-first, English is secondary)
- Code-switch: WER < 35% (harder — mixed tokens)

Run with `--noisy` flag to get WER across all SNR tiers.
