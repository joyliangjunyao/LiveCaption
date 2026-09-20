# Voice UI synchronization — 2026-09-20

Ported caption-only changes from the Voice variant:

- 340 × 108 initial/minimum floating window; startup resize preserves its top-left anchor.
- Empty-state message stays centered in the whole panel, at 12 pt.
- Removed toolbar separator; mouse-exit delay is 400 ms with a 120 ms fade.
- New installations use 14 pt for original text and translation. Existing user sizes remain.
- Increased line spacing and removed animated scrolling on text updates.
- Chinese full stops introduce display line breaks. Stored transcripts are unchanged.
  The Voice formatter also splits English periods indiscriminately; that behavior
  was not ported because it breaks decimals, URLs and abbreviations.

The shared toolbar controls, settings activation and resize implementation were
already largely identical. Voice-only controls and transient translation UI were
not copied into the final-result-only caption pipeline.

## Chinese recognition assessment

The Voice version calls an offline sherpa-onnx Paraformer executable, including
a fallback path inside Typeflux.app. Packaging reuses that installation's runtime.
Punctuation additionally depends on a separately installed Python interpreter and
FireRed/CT model resources. Caption recognition also calls personal vocabulary
and text helpers defined alongside voice-input code.

Do not transplant this pipeline as a UI patch. A portable integration needs an
independently sourced/pinned runtime, reviewed model notices, model installation
and verification, extracted shared text utilities, and audio regression coverage.
This release retains the repaired Whisper pipeline. UI synchronization does not
claim identical recognition accuracy or streaming behavior to Voice.

## Verification

Release build and signature verification passed after these presentation changes.
Launched the packaged app and visually checked the 340 × 108 panel and centered
empty-state message. No audio engine changes were made in this UI iteration, so
the previous full regression suite was not repeated. Pointer timing and live
subtitle scrolling were checked in code, not timed end-to-end.
