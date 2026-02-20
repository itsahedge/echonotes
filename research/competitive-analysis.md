# EchoNotes Competitive Analysis

*Research conducted February 2026*

---

## Market Overview

The AI meeting transcription space breaks into four categories:

1. **Bot-joins-call** — Otter.ai, Fireflies.ai, Read.ai (bot joins as a participant)
2. **System audio capture** — Alter, Jamie, Granola (captures device audio directly, no bot)
3. **Transcription-only** — MacWhisper, Whisper Notes (import or record audio, get text)
4. **Platform-native** — Zoom AI Companion, Google Meet, Microsoft Teams Copilot (locked to one platform)

**EchoNotes sits in category 2+3** — it captures system audio AND does on-device transcription. This is a unique combination.

---

## Competitor Deep Dives

### 1. MacWhisper

**What it is:** Mac transcription app powered by OpenAI Whisper and Nvidia Parakeet. Drag-and-drop audio files to get transcripts. Also available on iPhone/iPad.

**Pricing:**
- Free tier: Base and Small models only
- Pro: ~$79.99 one-time (Gumroad), or subscription via App Store (~$5/week)
- Controversial pricing history — was raised ~3x then rolled back after community backlash

**Key Features:**
- System-wide dictation (replaces Apple's built-in)
- Batch transcription
- Auto-record meetings in Zoom, Teams, Webex, Skype, Discord
- Full text and speaker search across all transcripts
- AI model support and translation
- Speaker identification

**Strengths:**
- Mature product, well-known in the Mac community
- Supports multiple Whisper model sizes (user chooses accuracy vs speed)
- Auto-record for specific meeting apps
- One-time purchase option (Gumroad)

**Weaknesses:**
- Pricing has been contentious — community sees it as overpriced
- Subscription model on App Store ($5/week = $260/year) is steep
- No AI summarization built-in
- Transcription-focused, not meeting-management

**Relevance to EchoNotes:**
MacWhisper is the most direct competitor for the "local Whisper on Mac" angle. EchoNotes' advantages: free, includes recording + transcription as a unified experience, speaker diarization via stereo split, and AI summarization.

---

### 2. Whisper Notes

**What it is:** $4.99 one-time purchase for iOS + Mac. Fully offline transcription. 60,000+ users.

**Pricing:**
- $4.99 once. No subscriptions, no ads, no in-app purchases

**Key Features:**
- 100% offline — app never connects to the internet after download
- Record voice or import audio files
- Fn key dictation in any Mac app (system-wide)
- 100+ language support
- Timestamp export
- Uses Whisper Large V3 Turbo model on Mac

**Strengths:**
- Dead simple — record, transcribe, done
- Incredible price point ($4.99 for Mac + iPhone)
- True privacy — no internet connection at all
- 60k+ users proves the market exists

**Weaknesses:**
- No real-time transcription (post-recording only)
- No speaker identification/diarization
- No AI summaries (by design — privacy stance)
- No meeting recording (mic only, no system audio capture)
- No meeting management features

**Relevance to EchoNotes:**
Whisper Notes proves the market for offline, privacy-first transcription at a low price. BUT it's a basic tool — no system audio capture, no diarization, no summaries. EchoNotes is significantly more featured. The $4.99 price point is a reference anchor — EchoNotes offers way more value and can justify a higher price.

---

### 3. Alter

**What it is:** Full-featured AI assistant for macOS with a strong meeting recording feature. Lives in the Mac menu bar/notch area.

**Pricing:**
- Free: Basic features + BYO API keys + local models (20-30 min meetings)
- Local+: Unknown exact price (limited to 3 devices)
- Pro: ~$24/month or ~$240/year
- Lifetime: One-time purchase (price varies, ~$300+)

**Key Features:**
- Auto-records every call (system audio + mic) across all platforms
- On-device transcription with speaker labels
- 30-second processing for 1-hour meetings
- Chat with your meetings (ask questions about past meetings)
- Automation: pull agendas from Notion, push summaries to CRM, action items to Linear
- 50+ integrated AI models
- Encrypted locally, no cloud needed for most languages

**Strengths:**
- **The most direct competitor to EchoNotes** — same approach (system audio capture + on-device transcription)
- Extremely polished Mac-native experience
- Auto-records everything (no manual start needed)
- Rich integration ecosystem (Notion, Slack, CRM, Linear)
- Strong Product Hunt reception
- General-purpose AI assistant (not just meetings)

**Weaknesses:**
- Expensive ($240/year or $24/month for full features)
- General-purpose = feature bloat for users who just want meeting transcription
- Fair use limits on AI model access (can get throttled)
- BYO API keys for free tier is confusing for non-technical users
- macOS only (no Windows, no mobile)

**Relevance to EchoNotes:**
Alter is the primary competitor. They've proven the "invisible system audio recording + on-device transcription" model works. Key EchoNotes differentiators: simpler/focused product (meetings only, not a general AI assistant), potentially lower price point, and WhisperKit (open-source ML) vs Alter's proprietary Parakeet model. Alter's weakness is complexity and price — EchoNotes can win on simplicity and affordability.

---

### 4. Jamie (meetjamie.ai)

**What it is:** AI meeting note-taker that captures computer audio directly. Available on Mac and Windows.

**Pricing:**
- Free: 10 meetings/month, 30-min limit
- Plus: €25/month (20 meetings, 2hr limit)
- Pro: €47/month (unlimited meetings, 3hr limit)
- Team: €39/seat/month
- Enterprise: Custom

**Key Features:**
- No bot joins the call — captures system audio
- Speaker recognition and memory (learns voices)
- Automatic task detection
- Works on all platforms (Zoom, Meet, Teams, etc.) + in-person
- Custom meeting templates
- Integrations: Notion, Google Docs, OneNote, Salesforce, HubSpot, Asana
- EU-hosted, GDPR compliant
- Mac AND Windows support

**Strengths:**
- Cross-platform (Mac + Windows) — bigger addressable market
- Strong integration story (CRM, project management tools)
- Speaker memory (improves over time)
- Task detection is a killer feature
- Professional team/enterprise features

**Weaknesses:**
- Expensive (€47/month for unlimited = €564/year)
- Cloud-based transcription (audio leaves your device)
- Not local/offline — requires internet
- Meeting count limits on lower tiers

**Relevance to EchoNotes:**
Jamie is what EchoNotes could become at scale — team features, integrations, speaker memory. But Jamie's transcription is cloud-based, which is the critical differentiator. EchoNotes' local-first approach is a direct counter-positioning: "Your audio never leaves your Mac." Jamie's €47/month price also creates massive room for EchoNotes to undercut.

---

### 5. Granola

**What it is:** AI "notepad" for meetings. Captures audio but positions itself as a note-taking enhancement rather than pure transcription.

**Pricing:**
- Free tier available
- Pro: $8.33/month (billed annually, ~$100/year) — 1,200 minutes
- Business: $18/month (unlimited meetings)
- Team: $14/user/month

**Key Features:**
- Captures meeting audio and enhances your notes with AI
- Works across Zoom, Meet, Teams
- Mac-native app
- You take rough notes during the meeting → AI fills in the gaps
- Strong community following (especially among VCs and founders)

**Strengths:**
- Unique positioning — it's a "notepad," not a transcription tool
- Very popular in tech/VC circles
- Reasonable pricing ($100/year)
- Clean UX — feels like a premium product
- Growing fast

**Weaknesses:**
- Not fully local — uses cloud AI for note enhancement
- Limited to a "notepad" metaphor — doesn't export raw transcripts easily
- No speaker diarization as a primary feature
- Only Mac (iOS app launched recently)

**Relevance to EchoNotes:**
Granola targets a different persona — people who want enhanced notes, not raw transcripts. EchoNotes and Granola could coexist. But Granola's success ($8-18/month) validates the market and pricing.

---

### 6. Otter.ai

**What it is:** The OG AI meeting assistant. Bot joins your call to record and transcribe.

**Pricing:**
- Free: 300 min/month, 30-min per conversation, 3 lifetime imports
- Pro: $6.67/month (annual) or $13.59/month — 1,200 min/month
- Business: Custom pricing — unlimited transcription
- Enterprise: Custom

**Key Features:**
- Automated bot joins Zoom, Teams, Google Meet
- Real-time live transcription
- Speaker identification by name
- AI Chat: ask questions across all your meetings
- Custom vocabulary for industry jargon
- Salesforce/HubSpot sync
- MCP server integration for AI assistants (new!)
- Mobile apps (iOS + Android)

**Strengths:**
- Market leader with massive brand recognition
- Excellent accuracy (cloud-based, unlimited compute)
- Team/enterprise features (admin controls, SSO, HIPAA)
- Cross-platform (web, mobile, desktop)
- AI Chat across meeting history is compelling

**Weaknesses:**
- **Bot joins the call** — visible to all participants, sometimes blocked by admins
- Cloud-based — all audio uploaded to Otter's servers
- Subscription model with minute limits
- Free tier is very limited (3 lifetime file imports)
- Can be unreliable in joining meetings

**Relevance to EchoNotes:**
Otter is the incumbent to position against. "Unlike Otter, EchoNotes doesn't join your call as a bot, doesn't upload your audio to the cloud, and doesn't charge monthly." Otter's weaknesses are EchoNotes' strengths.

---

### 7. Fireflies.ai

**What it is:** AI notetaker that joins meetings and provides transcription + analytics.

**Pricing:**
- Free: Limited transcription
- Pro: $10/user/month (annual) or $18/month
- Business: $19/user/month (annual)
- Enterprise: $39/user/month

**Key Features:**
- Bot joins Zoom, Teams, Meet, Webex
- Automated summaries, action items, key topics
- Meeting analytics (talk time, sentiment)
- AI-powered search across all meetings
- AskFred: AI assistant for meeting insights
- API and integrations (CRM, project management)
- Smart topic tracker

**Strengths:**
- Strong analytics features (talk ratios, sentiment)
- Good integration ecosystem
- Competitive pricing ($10/month for Pro)
- Works across all major platforms

**Weaknesses:**
- Bot-based — same visibility/admin issues as Otter
- Cloud-only transcription
- Credit system for AI features can be confusing
- Fair-use limits not always transparent

**Relevance to EchoNotes:**
Another bot-based competitor to position against. Fireflies' analytics features (sentiment, talk time) are interesting future features for EchoNotes.

---

### 8. Read.ai

**What it is:** AI meeting assistant with a desktop app for cross-platform meeting capture.

**Pricing:**
- Free: 5 meetings/month
- Pro: $19.75/month
- Enterprise: $29.75/month

**Key Features:**
- Desktop app works across Zoom, Teams, Meet, and in-person
- Real-time transcription
- Meeting engagement scores
- AI-generated summaries and action items
- Cross-platform search (meetings + emails + docs)
- Integrated with Zoom as an Essential App

**Strengths:**
- Desktop app approach (similar to EchoNotes — not bot-based)
- Cross-content search (meetings, emails, docs)
- Engagement scoring is unique
- Zoom partnership gives distribution advantage

**Weaknesses:**
- Expensive ($19.75/month)
- Cloud-based processing
- 5 meetings/month on free tier is very limited

**Relevance to EchoNotes:**
Read.ai's desktop app approach validates the "capture locally" model. Their engagement scoring and cross-content search are differentiated features worth watching.

---

## Competitive Matrix

| Feature | EchoNotes | Alter | Jamie | Granola | MacWhisper | Whisper Notes | Otter | Fireflies | Read.ai |
|---------|-----------|-------|-------|---------|------------|---------------|-------|-----------|---------|
| **Price** | TBD | $24/mo | €47/mo | $8-18/mo | $80 once | $4.99 once | $7-14/mo | $10-19/mo | $20/mo |
| **On-device transcription** | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **No bot joins call** | ✅ | ✅ | ✅ | ✅ | ✅ | N/A | ❌ | ❌ | ✅ |
| **System audio capture** | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | N/A | N/A | ✅ |
| **Speaker diarization** | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ | ✅ |
| **AI summaries** | ✅ (opt.) | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |
| **Works offline** | ✅ | Partial | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **Platform agnostic** | ✅ | ✅ | ✅ | ✅ | ✅ | N/A | ❌ | ❌ | ✅ |
| **macOS native** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| **Windows** | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| **Mobile** | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Team features** | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |
| **CRM integrations** | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| **Meeting analytics** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |

---

## Key Insights

### 1. The Privacy Gap is Real
Most competitors process audio in the cloud. The only fully local options are MacWhisper ($80), Whisper Notes ($4.99, no recording), and Alter (partial, $240/year). EchoNotes can own "completely local, completely private" at a competitive price.

### 2. Bot Fatigue is Growing
Users increasingly dislike bots joining their calls. Jamie, Granola, and Alter all market "no bot" as a primary selling point. This validates EchoNotes' approach.

### 3. Price Sensitivity is High
MacWhisper faced community backlash over pricing. Whisper Notes proved 60k people will pay $4.99. The sweet spot for a prosumer tool appears to be $20-30 one-time or $8-15/month.

### 4. AI Summaries are Table Stakes
Every competitor either has or is adding AI summaries. EchoNotes' optional OpenAI integration is the right approach — keep transcription free/local, charge for AI features.

### 5. Alter is the Primary Threat
Alter does almost exactly what EchoNotes does, is more mature, and has a polished Mac-native experience. But it's expensive ($240/year), complex (general-purpose AI assistant), and uses a proprietary transcription model. EchoNotes' advantage: simpler, cheaper, and built on open-source WhisperKit.

### 6. Features to Watch
- **Speaker memory** (Jamie) — learns voices over time, improves diarization
- **Meeting analytics** (Fireflies, Read.ai) — talk ratios, engagement, sentiment
- **Cross-meeting search** (Otter, Read.ai) — "what did we decide about X in any meeting?"
- **Auto-record** (Alter) — starts recording automatically when a meeting is detected
- **Task detection** (Jamie) — automatically extracts action items from conversation

---

## Recommended Positioning

**Tagline:** "Private meeting transcription for Mac. No bots. No cloud. No subscriptions."

**Target audience:** Privacy-conscious professionals (developers, lawyers, consultants, freelancers) who want meeting transcription without sending audio to the cloud or inviting a bot.

**Pricing recommendation:**
- **Option A (One-time):** $29 on the Mac App Store. Includes local transcription + diarization. AI summaries via BYO API key.
- **Option B (Freemium):** Free local transcription. $4.99/month or $29/year for AI summaries, advanced export, and future premium features.
- **Option C (Tiered one-time):** $19 base (transcription only), $39 pro (AI summaries, advanced features).

**Key differentiators to emphasize:**
1. 100% on-device — audio never leaves your Mac
2. No meeting bot — invisible recording
3. Works with any app — not locked to Zoom/Meet/Teams
4. One-time purchase — no subscription fatigue
5. Speaker identification without ML — lightweight stereo channel approach

---

*Last updated: February 2026*
