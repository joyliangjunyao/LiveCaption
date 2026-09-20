# Contributing

Use macOS 15 or later, Swift 6+, an installed Apple SDK, and CMake. Run
`./scripts/build-app.sh` first to build the native Whisper libraries, then
`swift test`. CLI provider tests additionally require explicit opt-in with
`LIVECAPTION_RUN_CLI_TESTS=1`; they may use an account and send sample text online.

Changes to audio buffering, recording, translation lifecycle or model downloads
should run the full suite. Check small documentation changes with a diff review;
check shell changes with `zsh -n scripts/build-app.sh`.

Never commit recordings, downloaded models, local account credentials or build
caches. Keep vendor licenses and record vendor updates in THIRD_PARTY_NOTICES.md.
Submit a focused change with its user-visible behavior and verification results.
