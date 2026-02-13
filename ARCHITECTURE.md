# EchoNotes Architecture

## Overview

Menu bar app that records audio from calls. Two input streams, one output file.

**🎤 AUDIO-ONLY APP** — We capture:
1. System audio output (other people on calls) via ScreenCaptureKit's audio API
2. Microphone input (your voice) via AVAudioEngine

No video, screen content, or visual data is captured.

## Audio Pipeline

```
┌─────────────────────────┐    ┌─────────────────────┐
│ SystemAudioCapture      │    │ MicrophoneCapture    │
│ ScreenCaptureKit        │    │ AVAudioEngine        │
│ (what you hear)         │    │ (what you say)       │
└───────────┬─────────────┘    └──────────┬───────────┘
            │                              │
            ▼                              ▼
┌──────────────────────────────────────────────────────┐
│                  AudioFileWriter                      │
│         System → Left channel (ch 0)                  │
│         Mic    → Right channel (ch 1)                 │
│         Output: M4A (AAC, 48kHz stereo)               │
└───────────────────────┬──────────────────────────────┘
                        │
                        ▼
              ~/Documents/EchoNotes/
              recording-2026-02-13T...m4a
```

## Components

| Component | File | Responsibility |
|-----------|------|---------------|
| EchoNotesApp | App/EchoNotesApp.swift | SwiftUI entry point |
| AppDelegate | App/AppDelegate.swift | NSStatusItem + NSPopover |
| RecordingEngine | App/RecordingEngine.swift | Coordinates capture + writing |
| SystemAudioCapture | Audio/SystemAudioCapture.swift | ScreenCaptureKit audio API (audio-only, no video) |
| MicrophoneCapture | Audio/MicrophoneCapture.swift | AVAudioEngine mic input |
| AudioFileWriter | Audio/AudioFileWriter.swift | Writes stereo M4A |
| MenuBarView | Views/MenuBarView.swift | Start/stop, timer, levels |
| PermissionChecker | Utils/Permissions.swift | Mic + screen recording |

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| System audio | ScreenCaptureKit | Modern Apple API, no kernel extensions |
| Mic capture | AVAudioEngine | Standard, low-latency |
| Output format | M4A (AAC) | Compressed, good quality, native macOS |
| Channel layout | Stereo (sys L, mic R) | Preserves both streams separately |
| Sample rate | 48kHz | Standard, high quality |
| Min macOS | 13.0 | ScreenCaptureKit requirement |
| Dependencies | None | Zero external deps for MVP |
