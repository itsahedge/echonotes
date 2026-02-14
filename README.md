# EchoNotes

> Record and transcribe calls on macOS. Any app. No bots. No cloud. Just audio.

EchoNotes is a native macOS menu bar app that records audio from **any** call — Zoom, Google Meet, FaceTime, Discord, phone calls, whatever — and transcribes it locally using [WhisperKit](https://github.com/argmaxinc/WhisperKit).

**🎤 AUDIO-ONLY APP** — We capture system audio output (other people on calls) and microphone input (your voice). No video, screen recording, or visual data whatsoever.

## Features

- **Universal recording** — works with any app that plays audio through your system
- **Live transcription** — see text appear in ~5-second intervals while you record
- **Post-recording transcription** — transcribe the full audio after you stop for higher accuracy
- **100% local** — all processing happens on-device via Apple's Neural Engine. No internet needed after model download.
- **Free** — no API keys, no accounts, no usage limits

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
```

## Requirements

- **macOS 14.0+** (Sonoma or later)
- **Apple Silicon** (M1 or later recommended for fast transcription)

## Setup

```bash
git clone <repo>
cd echonotes
swift build
# Or: open Package.swift in Xcode
```

On first launch, the app will download a Whisper model (~150MB for Base English).

### Permissions

macOS will ask for:
- **Microphone** — to capture your voice
- **Screen & System Audio Recording** — to capture system audio output

**Why "Screen Recording"?** macOS requires this permission to access ScreenCaptureKit's audio API. We use it in audio-only mode — no video or screen content is captured.

## Usage

1. Click the waveform icon in your menu bar
2. Choose transcription mode: **Live** or **After Recording**
3. Start a call in any app
4. Click **Start Recording**
5. Click **Stop Recording** when done
6. Your M4A + transcript are saved to `~/Documents/EchoNotes/`

## Transcription Modes

| Mode | How it works | Best for |
|------|-------------|----------|
| **Live** | Transcribes in ~5s chunks during recording | Seeing text as you talk |
| **After Recording** | Transcribes the full file after you stop | Higher accuracy |

## Project Structure

```
EchoNotes/
├── App/
│   ├── EchoNotesApp.swift          # Entry point (menu bar only)
│   ├── AppDelegate.swift           # Status item + popover
│   └── RecordingEngine.swift       # Coordinates capture + writing + transcription
├── Audio/
│   ├── SystemAudioCapture.swift    # ScreenCaptureKit (audio-only)
│   ├── MicrophoneCapture.swift     # AVAudioEngine mic input
│   └── AudioFileWriter.swift       # Stereo M4A output
├── Transcription/
│   ├── WhisperEngine.swift         # WhisperKit wrapper
│   ├── StreamingTranscriber.swift  # Live transcription (5s chunks)
│   ├── TranscriptionManager.swift  # Orchestrates transcription pipeline
│   └── ModelManager.swift          # Model loading + caching
├── Models/
│   └── Transcript.swift            # Segment model + export (.txt, .json)
├── Views/
│   ├── MenuBarView.swift           # Main popover UI
│   ├── RecordingControlsView.swift # Start/stop button
│   ├── TranscriptDisplayView.swift # Completed transcript display
│   └── LevelMeterView.swift        # Audio level visualization
└── Utils/
    ├── Constants.swift             # Audio configuration
    └── Permissions.swift           # Mic + screen recording checks
```

~1,770 lines of Swift + ~400 lines of tests. One dependency: [WhisperKit](https://github.com/argmaxinc/WhisperKit).

## Tech Stack

- **Swift / SwiftUI** — native macOS, menu bar app
- **ScreenCaptureKit** — system audio capture (audio-only mode)
- **AVAudioEngine** — microphone capture
- **WhisperKit** — on-device speech-to-text via CoreML + Apple Neural Engine
- **AAC/M4A** — compressed audio output

## License

Proprietary — All rights reserved.
