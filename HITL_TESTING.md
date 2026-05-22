# HITL_TESTING.md

## Why This Exists
Solo validation is costly. We minimize HITL by automating most checks, and reserve manual testing only for scenarios where human perception or live hardware variability matters.

## HITL-Only Focus Areas
1. Real-world microphone quality variance and room conditions
2. Driver/device route edge cases across headsets/speakers/USB interfaces
3. User-facing calibration prompt clarity and trustworthiness
4. Final release signoff confidence after automated suite is green

## Manual Session Protocol (Short Form)
1. Run automated suite first (see `AGENTIC_TESTING.md`)
2. Start app and confirm capture status messaging
3. Perform one live calibration phrase
4. Validate transcription behavior in realistic meeting conditions
5. Record findings in `session-state.json` and `RELEASE_CHECKLIST.md`

## Rule
No manual session should start from a red automated baseline unless explicitly debugging automation itself.

