# Data and network use

Audio recognition uses whisper.cpp locally. System audio and microphone capture
require macOS permissions. The application does not save screen images.

When recording is enabled, audio tracks and timestamped transcripts are saved in
the selected folder (by default Documents/LiveCaption). Transcripts are checkpointed
during recording; deleting these files is the user's responsibility. A crash may
still lose pending inference or writes that have not reached disk.

Network connections are used to download Whisper and speaker models and Apple
translation language packs. Models are cached in Application Support/LiveCaption
and framework-managed caches. No analytics or telemetry is implemented in the
application's own source.

Local summarization uses Apple's available on-device model, otherwise an extractive
summary. Selecting Codex CLI or Claude CLI sends the transcript to that program and
may upload it to its provider using the user's account. Audio is not passed to the
summary command. Custom CLI programs have their own behavior and permissions.
Do not select a program you do not trust. CLI integration tests are opt-in.
