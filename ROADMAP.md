# EchoNotes Roadmap

**🎤 AUDIO-ONLY APP** — All phases focus on audio capture, transcription, and AI notes. No video or screen recording features.

## Phase 1: Audio Capture MVP ← NOW

Record calls. Save to file. That's it.

- [x] System audio capture via ScreenCaptureKit (audio-only)
- [x] Microphone capture via AVAudioEngine
- [x] Write both streams to M4A (stereo: system L, mic R)
- [x] Menu bar app with start/stop, duration timer, level meters
- [x] Permission flow for mic + screen recording
- [x] Save to ~/Documents/EchoNotes/
- [x] Unit tests (AudioFileWriter, AudioFormats, TimestampedBuffer) — 11 passing
- [ ] Integration test: record a real call end-to-end
- [ ] Test across Zoom, Google Meet, FaceTime, Discord

## Phase 2: Whisper Transcription ← NEXT

Add local speech-to-text using OpenAI's Whisper model via whisper.cpp. Runs entirely on-device — no API keys, no internet, no cost.

### Integration Plan

**Dependencies:**
- [ ] Add whisper.cpp Swift package (`github.com/ggerganov/whisper.cpp`) to Package.swift
- [ ] Download Whisper model on first run (ggml-base.en ~150MB for English, ggml-small for multilingual ~500MB)
- [ ] Store models in `~/Library/Application Support/EchoNotes/Models/`

**Transcription Pipeline:**
- [ ] `WhisperEngine.swift` — wrapper around whisper.cpp C API
  - Load model once on app start, reuse across recordings
  - Accept M4A file path → convert to 16kHz mono WAV (Whisper's required format)
  - Run inference → return timestamped segments with text
- [ ] `TranscriptionManager.swift` — orchestrates the flow
  - Triggered automatically when recording stops (or manually via button)
  - Show progress indicator ("Transcribing... 45%")
  - Handle errors gracefully (model not downloaded, file corrupted, etc.)
- [ ] Audio format conversion: M4A stereo → 16kHz mono WAV
  - Use AVFoundation's `AVAudioConverter` (already familiar pattern from MicrophoneCapture)
  - Extract just the system audio channel (left) for transcription — that's the other person talking
  - Optionally transcribe both channels separately for speaker attribution

**Data Model:**
- [ ] `Transcript.swift` — array of segments, each with: start time, end time, text, confidence
- [ ] Save transcript as `.txt` and `.json` alongside the `.m4a` file
  - `recording-2026-02-13T18-00-00.m4a`
  - `recording-2026-02-13T18-00-00.txt` (plain text)
  - `recording-2026-02-13T18-00-00.json` (timestamped segments)

**UI:**
- [ ] "Transcribe" button in menu bar popover (shows after recording stops)
- [ ] Progress bar during transcription
- [ ] Simple transcript view — scrollable text with timestamps
- [ ] Copy transcript to clipboard button

**Performance Targets:**
- Base model (~150MB): ~10x real-time on M1 (1hr recording ≈ 6min to transcribe)
- Small model (~500MB): ~5x real-time on M1 (1hr recording ≈ 12min to transcribe)
- Default to base.en model for speed; let user pick larger models in settings

**Settings:**
- [ ] Model picker (tiny/base/small/medium) with download manager
- [ ] Language selection (or auto-detect)
- [ ] Transcribe automatically after recording (toggle, default off)

### Estimated Effort: 1-2 weeks

## Phase 3: AI Meeting Notes + OAuth (LATER)

After transcription, send to an LLM for structured notes. Authenticate via OAuth — no API keys.

### OAuth Authentication (Sign in, not paste keys)

Use `ASWebAuthenticationSession` for native macOS OAuth popups. Store tokens in Keychain.

**OpenAI (OAuth 2.0 PKCE):**
- [ ] Register OAuth app at `platform.openai.com` (get client_id)
- [ ] Implement PKCE flow: generate verifier/challenge → open `auth.openai.com/oauth/authorize` → catch callback on `127.0.0.1:<port>`
- [ ] Exchange authorization code for access + refresh tokens at `auth.openai.com/oauth/token`
- [ ] Store tokens in macOS Keychain (`Security.framework`)
- [ ] Auto-refresh: check `expires_at` before each API call, refresh transparently if expired
- [ ] UI: "Sign in with OpenAI" button in settings → browser popup → done

**Shared Auth Infrastructure:**
- [ ] `AuthManager.swift` — central auth coordinator, manages all provider tokens
- [ ] `KeychainStore.swift` — secure token storage via `Security.framework`
- [ ] `OAuthFlow.swift` — reusable PKCE flow (works for OpenAI + Google, extensible)
- [ ] Settings UI: "Sign in with OpenAI" button, connection status indicator
- [ ] Graceful degradation: if not connected, just save raw transcript

### AI Summarization

- [ ] Send transcript (or full audio for multimodal models) to connected provider
- [ ] Prompt: extract summary, action items, key decisions, open questions
- [ ] Generate: structured Markdown meeting notes
- [ ] Send audio directly to GPT-4o (multimodal — skip Whisper entirely if user prefers)
- [ ] Export meeting notes as Markdown file alongside recording

## Phase 4: Meeting Library (LATER)

- [ ] Browse past recordings, transcripts, and notes
- [ ] Search across all meetings (full-text search on transcripts)
- [ ] Filter by date, duration, keyword
- [ ] Export to Notion, Markdown, PDF
- [ ] Settings panel (save location, default model, auto-transcribe, etc.)
