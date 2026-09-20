# Release preparation — 2026-09-20

## Completed

- Buffered audio keeps every unprocessed sample when inference falls behind.
- Capture callbacks enqueue frames before scheduling UI delivery; stopping drains pending frames.
- Recording stop waits for recognizer work and short tails, then resumes captions if needed.
- Speaker-triggered recognition jobs participate in drain tracking.
- Recognized transcripts are checkpointed during recording; audio write failures are surfaced.
- The hang watchdog reports an unresponsive interface instead of terminating a recording.
- Whisper downloads check exact size, resume offset and pinned upstream SHA-256.
- MIT license, vendor notices, privacy documentation, contribution instructions and CI added.
- Vendor Git metadata moved outside the project; dependency sources are regular tracked files.

## Verification

Application release build and `codesign --verify --deep --strict` succeeded.
XCTest ran 13 cases: 12 passed, 1 skipped, 0 failures. The skipped test explicitly
calls installed cloud CLI providers; no live cloud summary was requested.
Shell syntax, plist validity, first-party whitespace and a common credential-pattern
scan passed. Vendor sources still produce upstream compiler warnings.

This Mac's selected Xcode requires license setup. Verification used Command Line
Tools Swift 6.4, the installed macOS 26.5 SDK, and the installed Xcode XCTest runner
directly after building the test bundle. A normal fully configured Xcode installation
can use the documented `swift test` command. CI has been configured, but has not
run remotely yet.

No live microphone/system-audio end-to-end test, hardware-disconnection test or
Developer ID notarization was performed. Unit tests establish buffer/persistence
behavior, not an ASR accuracy guarantee. Pending inference and unwritten OS buffers
can still be lost on power failure; checkpoints preserve completed text.

No remote repository was created and nothing has been publicly uploaded.
