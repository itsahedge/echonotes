# EchoNotes

> Private meeting transcription for Mac. No bots. No cloud. No subscriptions.

EchoNotes is a native macOS desktop app that records audio from **any** call — Zoom, Google Meet, FaceTime, Discord, phone calls, whatever — and transcribes it locally using [WhisperKit](https://github.com/argmaxinc/WhisperKit). Optionally generate AI-powered meeting summaries with your existing ChatGPT subscription or any API key.

**🎤 AUDIO-ONLY APP** — We capture system audio output (other people on calls) and microphone input (your voice). No video, screen recording, or visual data whatsoever.

## Features

- **Universal recording** — works with any app that plays audio through your system
- **Live transcription** — see text appear in ~5-second intervals while you record
- **Post-recording transcription** — transcribe the full audio after you stop for higher accuracy
- **Speaker diarization** — distinguish between different speakers in the transcript
- **Recording library** — browse, search, and manage all your recordings with full-text search
- **AI summaries** — generate structured meeting summaries (key points, action items, decisions)
- **Multi-provider AI** — OpenAI, Anthropic, Google Gemini, or local Ollama
- **ChatGPT OAuth** — sign in with your existing ChatGPT Plus/Pro subscription (no API key needed)
- **Global hotkey** — start/stop recording with ⌘⇧R from anywhere
- **100% local transcription** — all speech-to-text happens on-device via Apple's Neural Engine
- **Free** — no accounts or usage limits for recording and transcription

## How It Works

```
ScreenCaptureKit (system audio) ──→ Left channel  ──┐
                                                     ├──→ Stereo M4A
AVAudioEngine (microphone)      ──→ Right channel ──┘
                                                         │
                                              WhisperKit (CoreML)
                                                         │
                                                    Transcript
                                                  (.txt + .json)
                                                         │
                                              AI Provider (optional)
                                                         │
                                                 Meeting Summary
                                          (key points, actions, decisions)
```

## Requirements

- **macOS 14.0+** (Sonoma or later)
- **Apple Silicon** (M1 or later recommended for fast transcription)

## Build & Run

```bash
git clone <repo>
cd echonotes
```

### Build the app (recommended)

```bash
./scripts/build-app.sh
```

This creates `EchoNotes.app` in the project root. Double-click to launch, or drag to `/Applications` to install.

### Run from Xcode

```bash
open Package.swift
```

Press **⌘R** to build and run.

### Run from command line (debug)

```bash
swift build
.build/debug/EchoNotes
```

On first launch, the app downloads a Whisper model (~150MB for Base English). This only happens once.

### Permissions

macOS will ask for:
- **Microphone** — to capture your voice
- **Screen & System Audio Recording** — to capture system audio output

**Why "Screen Recording"?** macOS requires this permission to access ScreenCaptureKit's audio API. We use it in audio-only mode — no video or screen content is captured.

## Usage

1. Launch EchoNotes — a window opens with a sidebar and detail area
2. Choose transcription mode in the toolbar: **Live** or **After Recording**
3. Start a call in any app
4. Click **Record** in the toolbar (or press **⌘⇧R**)
5. Click **Stop** when done
6. Your M4A + transcript are saved to `~/Documents/EchoNotes/`
7. Select a recording in the sidebar to view the transcript
8. Click **Ask EchoNotes** to generate an AI summary
9. Open **Settings** (⌘,) to configure AI provider, Whisper model, and transcription defaults

## AI Summarization

EchoNotes can generate structured meeting summaries from your transcripts. Configure in **Settings** (⌘,) → **AI** tab:

### Option 1: ChatGPT Sign-In (no API key needed)
Click **Sign in with ChatGPT** to use your existing Plus/Pro subscription. Uses OAuth 2.1 + PKCE to authenticate, then calls the ChatGPT backend Responses API directly.

### Option 2: API Key
Paste an API key for any supported provider:
- **OpenAI** — `api.openai.com`
- **Anthropic** — Claude models
- **Google Gemini** — Gemini models
- **Ollama** — local models (no key needed)

## Project Structure

```
EchoNotes/
├── AI/
│   ├── AIProvider.swift             # Multi-provider config (OpenAI, Anthropic, Google, Ollama)
│   └── AIService.swift              # Summarization logic + ChatGPT backend streaming
├── App/
│   ├── EchoNotesApp.swift           # Entry point (WindowGroup + Settings scene)
│   ├── AppDelegate.swift            # Owns shared state (RecordingEngine, RecordingLibrary)
│   └── RecordingEngine.swift        # Coordinates capture + writing + transcription
├── Audio/
│   ├── SystemAudioCapture.swift     # ScreenCaptureKit (audio-only)
│   ├── MicrophoneCapture.swift      # AVAudioEngine mic input
│   └── AudioFileWriter.swift        # Stereo M4A output
├── Auth/
│   ├── OAuthManager.swift           # OAuth 2.1 + PKCE flow, JWT parsing, token storage
│   └── OAuthCallbackServer.swift    # Local HTTP server for OAuth redirect
├── Models/
│   ├── Recording.swift              # Recording model + library management
│   ├── Speaker.swift                # Speaker enum for diarization
│   └── Transcript.swift             # Segment model + export (.txt, .json)
├── Transcription/
│   ├── WhisperEngine.swift          # WhisperKit wrapper
│   ├── StreamingTranscriber.swift   # Live transcription (5s chunks)
│   ├── TranscriptionManager.swift   # Orchestrates transcription + AI config + OAuth state
│   └── ModelManager.swift           # Model loading + caching
├── Views/
│   ├── MainWindowView.swift         # Root NavigationSplitView (sidebar + detail)
│   ├── SidebarView.swift            # Sidebar meeting list with search
│   ├── ActiveRecordingView.swift    # Recording session UI (timer, levels, live transcript)
│   ├── RecordingDetailView.swift    # Transcript + AI summary with DisclosureGroups
│   ├── DesktopSettingsView.swift    # Tabbed Settings window (General, AI, About)
│   ├── SettingsView.swift           # AI provider config + OAuth sign-in
│   ├── LibraryView.swift            # Recording library (date formatter shared)
│   ├── RecordingControlsView.swift  # Start/stop button
│   ├── SummaryView.swift            # Meeting summary display
│   ├── TranscriptDisplayView.swift  # Completed transcript display
│   └── LevelMeterView.swift         # Audio level visualization
├── Utils/
│   ├── Constants.swift              # Audio configuration
│   └── Permissions.swift            # Mic + screen recording checks
├── scripts/
│   └── build-app.sh                 # Build release app bundle
├── research/
│   └── competitive-analysis.md      # Market research
├── CLAUDE.md                        # AI coding assistant rules
├── CONTRIBUTING.md                  # Build + test requirements for PRs
└── EchoNotesTests/                  # ~90 tests across 10 files
```

## Tech Stack

- **Swift / SwiftUI** — native macOS desktop app with NavigationSplitView
- **SwiftPM** — package management (no Xcode project file needed)
- **ScreenCaptureKit** — system audio capture (audio-only mode)
- **AVAudioEngine** — microphone capture
- **WhisperKit** — on-device speech-to-text via CoreML + Apple Neural Engine
- **Network.framework** — OAuth callback server (NWListener)
- **AAC/M4A** — compressed audio output

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Every PR must:
1. Pass `./scripts/build-app.sh`
2. Include tests for new functionality
3. Use feature branches (never push directly to main)

## License

Proprietary — All rights reserved.
