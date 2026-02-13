# EchoNotes Roadmap

**🎤 AUDIO-ONLY APP** — All phases focus on audio capture, transcription, and AI notes. No video or screen recording features.

## Phase 1: Audio Capture MVP (NOW)

Record calls. Save to file. That's it.

- [ ] System audio capture via ScreenCaptureKit (audio-only)
- [ ] Microphone capture via AVAudioEngine
- [ ] Write both streams to M4A (stereo: system L, mic R)
- [ ] Menu bar app with start/stop, duration timer, level meters
- [ ] Permission flow for mic + screen recording
- [ ] Save to ~/Documents/EchoNotes/
- [ ] Test across Zoom, Google Meet, FaceTime, Discord

## Phase 2: Local Transcription (LATER)

- [ ] Integrate whisper.cpp for local speech-to-text
- [ ] Post-recording transcription (not real-time)
- [ ] Save transcript alongside audio file
- [ ] Basic transcript viewer in the app

## Phase 3: AI Summarization (LATER)

- [ ] Send transcript to LLM for summary
- [ ] Extract action items and key decisions
- [ ] Export meeting notes as Markdown

## Phase 4: Meeting Library (LATER)

- [ ] Browse past recordings and transcripts
- [ ] Search across meetings
- [ ] Export to Notion, Markdown, PDF
- [ ] Settings panel (model selection, save location, etc.)
