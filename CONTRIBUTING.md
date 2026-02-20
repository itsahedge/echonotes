# Contributing to EchoNotes

## Build & Test Rule (Mandatory)

**Every PR must build cleanly and include tests. No exceptions.**

### Before Opening a PR

1. **Build must succeed:** `./scripts/build-app.sh` (or `xcodebuild`) with zero errors
2. **Tests must pass:** `xcodebuild test` with zero failures
3. **New code must have tests:**
   - Bug fixes: add a test that reproduces the bug
   - New features: add tests covering the core logic
   - Refactors: existing tests must still pass; add tests if behavior changes

### What Needs Tests

- **Model logic** (Transcript, RecordingLibrary, MeetingSummary, Speaker) — always
- **Parsing / serialization** (JSON encode/decode, .txt fallback, response parsing) — always
- **Manager methods** (TranscriptionManager, AIService) — test with mocks where possible
- **Views** — SwiftUI previews at minimum; snapshot tests if available

### What Can Skip Tests

- Pure SwiftUI layout changes (colors, padding, spacing)
- Asset changes (icons, images)
- Documentation-only changes

### Build Errors Are Blocking

If a PR introduces a build error (wrong init parameters, missing imports, type mismatches), it must be caught before merge. The build script is the source of truth.

---

*This rule exists because we shipped multiple build-breaking PRs. Never again.*
