# NOISE_SIMULATION.md

## Goal
Standardize noisy-environment simulation for VAD/LID/transcription regression using reproducible SNR tiers.

## Reference Paths (Project-Relative)
1. Clean speech fixtures: `test_fixtures/wav16k/*.wav`
2. Noise fixtures: `test_fixtures/wav16k/noise_fan.wav`, `test_fixtures/wav16k/music_bg.wav`
3. Output noisy variants: `test_fixtures/noisy_variants/`

## SNR Tiers (dB)
Use all tiers below for each speech fixture:
1. `30` (very easy)
2. `20` (easy)
3. `15` (moderate)
4. `10` (challenging)
5. `5` (hard)
6. `0` (very hard)
7. `-5` (extreme)
8. `-10` (stress only; non-blocking)

## Naming Convention
`<speech_id>__<noise_id>__snr_<plus|minus><N>dB.wav`

Examples:
1. `en_clean__noise_fan__snr_plus10dB.wav`
2. `hi_clean__music_bg__snr_minus5dB.wav`

## FFmpeg Mix Model
Use `amix` with noise gain chosen per SNR.

Relationship:
`noise_gain_linear = 10^(-SNR_dB/20)`

Examples:
1. SNR +20 dB -> gain `0.1`
2. SNR +10 dB -> gain `0.3162`
3. SNR 0 dB -> gain `1.0`
4. SNR -5 dB -> gain `1.7783`

## Command Template
```bash
ffmpeg -y \
  -i <speech.wav> \
  -stream_loop -1 -i <noise.wav> \
  -filter_complex "[1:a]volume=<NOISE_GAIN>[n];[0:a][n]amix=inputs=2:duration=first:dropout_transition=0[m]" \
  -map "[m]" -ac 1 -ar 16000 -sample_fmt s16 \
  <out.wav>
```

## Expected Test Policy by SNR Tier

### Blocking tiers (release gate)
1. `+20, +15, +10, +5 dB`
2. Expectations:
   - VAD speech recall stays high
   - LID stable for single-language clips
   - No pipeline stall/crash

### Conditional tiers
1. `0, -5 dB`
2. Expectations:
   - VAD may degrade but should not collapse
   - LID may fluctuate; allow top-k or confidence fallback
   - No stall/crash

### Stress-only (non-blocking)
1. `-10 dB`
2. Expectation:
   - System remains alive, logs degradation, does not deadlock.

## Minimal Acceptance Matrix
Per speech clip x per noise type:
1. Blocking pass: `+20,+15,+10,+5`
2. Survival pass: `0,-5,-10` (no crash/stall)

## CI Integration
1. Generate variants before `flutter test`.
2. Run model/pipeline tests against generated files.
3. Archive failures and sample waveforms as CI artifacts.

