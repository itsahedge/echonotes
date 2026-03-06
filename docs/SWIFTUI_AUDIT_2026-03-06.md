# SwiftUI Code Quality Audit

**Date:** 2026-03-06
**Target:** macOS 14+, Swift 6.2, SwiftUI
**Skill used:** swiftui-pro (twostraws/swiftui-agent-skill)

---

## Priority 1: High

### 1.1 `@AppStorage` in `ObservableObject` — RecordingEngine

**File:** `EchoNotes/App/RecordingEngine.swift` (lines 29-31)

`@AppStorage` inside `ObservableObject` can cause SwiftUI re-render loops. The project's own CLAUDE.md warns against this pattern. `TranscriptionManager` already uses the correct `@Published` + `UserDefaults` pattern.

**Affected properties:**
- `autoTranscribe`
- `transcriptionModeRaw`
- `selectedSourceId`
- `selectedSystemSourceId`

**Fix:** Migrate to `@Published` with `didSet` writing to `UserDefaults`, matching `TranscriptionManager`'s existing pattern.

```swift
// Before
@AppStorage("autoTranscribe") var autoTranscribe = false

// After
@Published var autoTranscribe: Bool = UserDefaults.standard.bool(forKey: "autoTranscribe") {
    didSet { UserDefaults.standard.set(autoTranscribe, forKey: "autoTranscribe") }
}
```

---

## Priority 2: Medium

### 2.1 Deprecated API: `cornerRadius()` (10+ instances)

`.cornerRadius()` is deprecated. Replace with `.clipShape(.rect(cornerRadius:))`.

**Files affected:**
- `MainWindowView.swift:152`
- `RecordingDetailView.swift:239, 310`
- `SettingsView.swift:99, 232`
- `DesktopSettingsView.swift` (via child views)
- `ActiveRecordingView.swift:29`
- `LibraryView.swift:50, 117`

```swift
// Before
.cornerRadius(8)

// After
.clipShape(.rect(cornerRadius: 8))
```

### 2.2 Deprecated API: `foregroundColor()` (2 instances)

`.foregroundColor()` is deprecated. Replace with `.foregroundStyle()`.

**Files affected:**
- `SettingsView.swift:293`
- `RecordingDetailView.swift:293` (if connection test result display was copied)

```swift
// Before
.foregroundColor(result.success ? .primary : .red)

// After
.foregroundStyle(result.success ? .primary : .red)
```

### 2.3 GCD usage instead of Swift Concurrency

`DispatchQueue.main.asyncAfter` should be replaced with `Task.sleep(for:)`.

**File:** `SettingsView.swift:188`

```swift
// Before
DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }

// After
Task {
    try? await Task.sleep(for: .seconds(2))
    saved = false
}
```

### 2.4 Search filtering uses `.contains()` instead of `localizedStandardContains()`

User-entered search text should use locale-aware matching for correct accent/case handling.

**File:** `EchoNotes/Models/RecordingLibrary.swift:70-72`

```swift
// Before
entry.filename.lowercased().contains(query) ||
(entry.fullTranscriptText?.lowercased().contains(query) ?? false)

// After
entry.filename.localizedStandardContains(searchQuery) ||
(entry.fullTranscriptText?.localizedStandardContains(searchQuery) ?? false)
```

### 2.5 Dead code: unused view files

After the desktop redesign, these files appear orphaned:

- **`SidebarView.swift`** — references `navigationSplitViewColumnWidth` and `navigationTitle` which don't apply to the current HStack layout. `MainWindowView` has its own inline sidebar.
- **`RecordingControlsView.swift`** — Record/Stop logic is now inline in `MainWindowView.toolbarContent`.

**Fix:** Verify these are unused and delete them.

### 2.6 Missing `.summary.json` cleanup in delete

`RecordingLibrary.delete()` removes `.m4a`, `.txt`, `.json`, and `.md` files but not `.summary.json`.

**File:** `EchoNotes/Models/RecordingLibrary.swift:134-139`

```swift
// Before
let urls = [
    entry.url,
    entry.url.deletingPathExtension().appendingPathExtension("txt"),
    entry.url.deletingPathExtension().appendingPathExtension("json"),
    entry.url.deletingPathExtension().appendingPathExtension("md"),
]

// After
let urls = [
    entry.url,
    entry.url.deletingPathExtension().appendingPathExtension("txt"),
    entry.url.deletingPathExtension().appendingPathExtension("json"),
    entry.url.deletingPathExtension().appendingPathExtension("md"),
    entry.url.deletingPathExtension().appendingPathExtension("summary.json"),
]
```

---

## Priority 3: Low

### 3.1 Empty states should use `ContentUnavailableView`

Several places manually build empty-state UI. SwiftUI's built-in `ContentUnavailableView` provides standard styling and accessibility for free.

**Files affected:**
- `MainWindowView.swift:202-210` (no recordings)
- `MainWindowView.swift:212-214` (no search results)
- `LibraryView.swift:55-62`
- `SidebarView.swift:30-38`

```swift
// Before
VStack(spacing: 8) {
    Image(systemName: "waveform.slash")
        .font(.system(size: 30))
        .foregroundStyle(.secondary)
    Text("No recordings yet")
        .font(.callout)
        .foregroundStyle(.secondary)
}

// After
ContentUnavailableView("No recordings yet", systemImage: "waveform.slash")
```

### 3.2 View decomposition — large files with many computed properties

Best practice is to extract computed properties returning `some View` into separate `View` structs in their own files. The largest offenders:

| File | Computed properties to extract |
|------|-------------------------------|
| `MainWindowView.swift` | `appSidebar`, `meetingListPanel`, `meetingDetailPanel`, `toolbarContent`, `emptyStateView`, `readyToTranscribeView` |
| `RecordingDetailView.swift` | `summarySection`, `transcriptSection`, `summaryCard`, `bulletItem`, `aiButtonSection` |
| `SettingsView.swift` | `oauthSection`, `aiProviderSection`, `customEndpointSection` |
| `DesktopSettingsView.swift` | `developerContent`, `knowledgeBaseContent` |

### 3.3 Force unwraps on `FileManager` — use modern `URL.documentsDirectory`

**Files affected:**
- `RecordingEngine.swift:67`
- `RecordingLibrary.swift:77`

```swift
// Before
let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

// After
let docs = URL.documentsDirectory
```

### 3.4 Redundant `MainActor.run` in `TranscriptionManager`

`TranscriptionManager` is `@MainActor`. Tasks created inside it inherit main actor isolation. The `MainActor.run {}` wrappers are unnecessary.

**File:** `EchoNotes/Transcription/TranscriptionManager.swift`
- Lines 233, 236, 256-258, 264-267, 270-272

### 3.5 Unnecessary `import AppKit`

When `import SwiftUI` is present, `AppKit` is imported automatically on macOS.

**Files affected:**
- `EchoNotes/App/EchoNotesApp.swift:2`
- `EchoNotes/App/AppDelegate.swift:1`

### 3.6 Use `Date.now` instead of `Date()`

Minor clarity improvement.

**Files affected:**
- `RecordingEngine.swift:104` — `Self.recordingTimestampFormatter.string(from: Date())`
- `RecordingEngine.swift:210` — `recordingStartTime = Date()`

### 3.7 `ForEach` over `enumerated()` — avoid `Array()` conversion

Multiple files wrap `enumerated()` in `Array()`. If `TranscriptSegment` conforms to `Identifiable`, the array conversion is unnecessary.

**Files affected:**
- `ActiveRecordingView.swift:78`
- `RecordingDetailView.swift:283`
- `TranscriptDisplayView.swift:84`

```swift
// Before
ForEach(Array(items.enumerated()), id: \.offset) { _, segment in

// After (if TranscriptSegment: Identifiable)
ForEach(items.enumerated(), id: \.element.id) { _, segment in
```

### 3.8 `SummaryView.swift` uses `.caption` fonts from menu bar era

Now displayed in a full desktop window, fonts should be scaled up.

**File:** `EchoNotes/Views/SummaryView.swift` — lines 17-18, 26-27, 67-79

### 3.9 Business logic in views

`RecordingDetailView.generateSummary()` contains network calls and file I/O. This should be extracted to a service/view model for testability.

**File:** `EchoNotes/Views/RecordingDetailView.swift:315-358`

---

## Not flagged (acceptable)

- `GeometryReader` in `LevelMeterView` — legitimate use for proportional fill width
- Google Gemini API key in URL — required by their API design
- `Timer.scheduledTimer` in `RecordingEngine` — acceptable for UI duration updates
- `ObservableObject` / `@Published` pattern — legacy but changing architecture would be disruptive; acceptable per skill rules
