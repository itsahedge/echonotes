# CLAUDE.md

## Build Verification

**Every PR must pass `./scripts/build-app.sh` before pushing.** No exceptions.

If the build fails, fix it before committing. Do not push broken code and fix it in a follow-up.

## Project Structure

- **Language:** Swift (SwiftPM, not Xcode project)
- **Platform:** macOS 14+ menu bar app (`LSUIElement = true`)
- **Build:** `./scripts/build-app.sh` (release build + app bundle)
- **Tests:** `swift test`

## Key Directories

- `EchoNotes/AI/` — AI provider integrations (OpenAI, Anthropic, Google, Ollama)
- `EchoNotes/Auth/` — OAuth 2.1 + PKCE flow for ChatGPT subscription auth
- `EchoNotes/Audio/` — Microphone and system audio capture
- `EchoNotes/Transcription/` — WhisperKit on-device transcription
- `EchoNotes/Views/` — SwiftUI views (Settings, RecordingDetail, Library)
- `EchoNotes/Models/` — Data models (Recording, Speaker, etc.)

## Architecture Notes

- `TranscriptionManager` is the main `@ObservableObject` — owns AI settings, OAuth state, and transcription logic
- **Nested ObservableObjects need manual forwarding** — `oauthManager.objectWillChange` is piped through Combine to `TranscriptionManager.objectWillChange`
- **Use `@Published` + `UserDefaults`** for settings, NOT `@AppStorage` inside `ObservableObject` (causes SwiftUI re-render loops)
- **No Keychain for API keys** — triggers macOS permission dialogs, `UserDefaults` is sufficient for sandboxed app
- `AIService.Configuration` supports both API key auth and ChatGPT backend auth (`chatgptAccountId` header)

## Common Pitfalls

- Watch for brace balance when editing Swift files — stray `}` can close a class early
- `swift build` uses SPM, not xcodebuild — no `.xcodeproj` needed
- The app is a menu bar app — no dock icon, no main window by default
