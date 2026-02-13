# EchoNotes

> Record calls on macOS. Any app. No bots. Just audio.

EchoNotes is a native macOS menu bar app that records audio from **any** call — Zoom, Google Meet, FaceTime, Discord, phone calls, whatever. Click to start, click to stop, get an M4A file.

**🎤 AUDIO-ONLY APP** — We capture system audio output (other people on calls) and microphone input (your voice). No video, screen recording, or visual data whatsoever.

## What It Does

1. **Menu bar icon** — click to start recording, click to stop
2. **Captures system audio** (what you hear) via ScreenCaptureKit
3. **Captures microphone** (what you say) via AVAudioEngine
4. **Saves to M4A** — system audio on left channel, mic on right
5. That's it.

## Requirements

- **macOS 13.0+** (Ventura or later)
- **Xcode 15.0+** / Swift 5.9+

## Setup

```bash
git clone <repo>
cd echonotes
open Package.swift  # Opens in Xcode
# Or: swift build
```

### Permissions

On first launch, macOS will ask for:
- **Microphone** — to capture your voice
- **Screen & System Audio Recording** — to capture system audio output (other people on calls)

**Why "Screen Recording"?** macOS requires this permission to access ScreenCaptureKit's audio API. We use ScreenCaptureKit in audio-only mode — no video, screen, or visual data is captured.

## How It Works

```
ScreenCaptureKit (system audio) ──→ Left channel  ──┐
                                                     ├──→ M4A file
AVAudioEngine (microphone)      ──→ Right channel ──┘
```

Recordings are saved to `~/Documents/EchoNotes/`.

## Project Structure

```
EchoNotes/
├── App/
│   ├── EchoNotesApp.swift      # Entry point
│   ├── AppDelegate.swift       # Menu bar + popover
│   └── RecordingEngine.swift   # Coordinates capture + file writing
├── Audio/
│   ├── SystemAudioCapture.swift  # ScreenCaptureKit audio-only
│   ├── MicrophoneCapture.swift   # AVAudioEngine mic input
│   ├── AudioMixer.swift          # TimestampedBuffer type
│   └── AudioFileWriter.swift     # M4A file output
├── Views/
│   └── MenuBarView.swift         # Start/stop, duration, levels
└── Utils/
    ├── Permissions.swift         # Mic + screen recording checks
    └── AudioFormats.swift        # RMS level calculation
```

Zero external dependencies.

## License

Proprietary — All rights reserved.
