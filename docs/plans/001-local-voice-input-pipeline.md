# vkey — Local Voice Input App Implementation Plan (Multi-language + Queuing Parallel Pipeline)

## Context (Why We're Building This)

Based on `~/Downloads/keyvoice_local_only_implementation_plan.md` (initial plan created by ChatGPT),
we are building a push-to-talk voice input app for macOS 26+ that runs entirely locally using only Apple's native frameworks.
It records audio while a key is held down → transcribes (via Speech) → faithfully formats the text (via Foundation Models) → inserts into the focused app.

The following essential requirements were added and revised by the developer relative to the initial plan. This plan is a redesign with these at its core.

1. **Multi-language support from the start.** Not fixed to Japanese — the user must be able to choose the language. The language must be determined before recording (see below).
2. **Processing segmentation for token limit handling.** Apple's on-device model has a **4096-token limit per session** (including input + instructions + output). Long utterances must be split into chunks after transcription before formatting.
   - Reference: RevComm article (https://tech.revcomm.co.jp/foundation-models-proto). Key insights: 4096 limit, Map-Reduce splitting, per-session generation, measured performance ~5000 chars≈10s / ~15000 chars≈30-60s. This app performs "formatting" not "summarization," so no Reduce step is needed — Map (parallel chunk formatting) → join in index order is sufficient.
3. **Queuing mechanism.** ① Accept the next recording even while processing an utterance, and process them in order. ② Multiple chunks within a single utterance are formatted **in parallel** (not serially) to improve throughput. ③ However, final insertion strictly follows **utterance FIFO order × chunk order within each utterance**.

### Confirmed Technical Premises (Researched)
- Foundation Models: **4096-token** limit per session. Throws `LanguageModelSession.GenerationError.exceededContextWindowSize` when exceeded. In macOS **26.4**, the `SystemLanguageModel.contextSize` property and `tokenCount(for:)` method were added, enabling pre-measurement of token counts.
- The on-device model is a **single system-shared resource**. Running multiple sessions in parallel may be serialized in actual hardware, making parallelization gains uncertain → **make concurrency configurable (tunable) and determine by measurement**.
- Speech (macOS 26's `SpeechAnalyzer`/`SpeechTranscriber`) **requires the locale to be determined before recording**. Automatic language detection from audio is structurally impossible → language must be pre-selected.
- Distribution assumes Developer ID + notarization. Mac App Store / Sandbox is not considered.

### Developer-Confirmed Decisions (Answers to Questions)
- **Language switching UX**: Display the current language in the menu bar (popover) and switch quickly with one click. Select before recording.
- **Initial supported languages**: All major languages (languages for which Speech assets are available and that Foundation Models can handle) as options from the start. Formatting prompts use a language-agnostic template (see below) to scale to N languages; quality validation is kept lightweight.

### Current State
- `vkey` / `vkey.xcodeproj` is a newly scaffolded SwiftUI project (only defaults: `vkeyApp.swift` + `ContentView.swift`). `docs/` is empty. Implementation from scratch.
- Build verification is done using the MCP **xcode** tool (AGENTS.md).

---

## Overall Architecture

**Complete separation of the three ordering layers** is the core of the design. This achieves "fast parallel processing while strict FIFO for insertion."

- **Utterance receipt order** = `seq` (FIFO is finalized the instant it is assigned when recording stops)
- **Chunk order within utterance** = `chunkIndex` (restored by writing back to index slots even after parallel formatting)
- **Insertion order** = `InsertionSerializer` strictly waits for ascending `seq` in a re-ordering buffer

```
[PTT Recording (exclusive)] ──stop──▶ seq assignment (immediate) ──▶ AsyncStream
   │                                          │
   └─ next recording accepted immediately     ┌────────────▼──────────────┐
                                              │ PipelineCoordinator        │
                                              │  controls utterance-level  │
                                              │  concurrency via           │
                                              │  bounded-pump              │
                                              │  (maxConcurrentUtterances) │
                                              └────────────┬──────────────┘
                           ┌───────────────────▼────────────────┐
                           │ UtteranceProcessor (per utterance)  │
                           │ 1. Transcribe (Speech)              │
                           │ 2. Chunk split (tokenCount)         │
                           │ 3. TaskGroup parallel format ────┐  │
                           │ 4. join in index order           │  │
                           └──────────────┬───────────────────┘  │
                                          │   ┌──────────────────▼──────────────┐
                                          │   │ GlobalModelLimiter               │
                                          │   │ controls model concurrency       │
                                          │   │ across all utterances            │
                                          │   │ (maxConcurrentModelCalls)        │
                                          │   └──────────────────────────────────┘
                           ┌──────────────▼───────────────┐
                           │ InsertionSerializer (actor)   │
                           │ strictly serializes insertion │
                           │ in ascending seq order        │
                           └──────────────┬───────────────┘
                               ┌──────────▼──────────┐
                               │ TextInserter         │
                               │ AX insert → CB fallback │
                               └──────────────────────┘
```

### Two Concurrency Knobs (Orthogonal to Each Other; Neither Affects Order Guarantees)

| Knob | Controls | Purpose |
|---|---|---|
| `maxConcurrentModelCalls` (GlobalModelLimiter) | Total simultaneous model calls across all utterances | Verify whether the on-device model parallelizes in real hardware. `1` = serial baseline |
| `maxConcurrentUtterances` (PipelineCoordinator) | Number of utterances in concurrent processing (stage overlap) | Pipeline Speech↔Model↔Insertion (begin transcribing utterance n+1 while formatting n) |

Both knobs are independent of ordering guarantees, so no matter how they are set, insertion results are always "utterance FIFO × chunk order." Initial values: `maxConcurrentModelCalls=1`, `maxConcurrentUtterances=2`; tune by measurement.

### Invariant Ensuring Order Guarantees (Most Important)
> **Every assigned `seq`, whether it succeeds, fails, is silent, or is cancelled, must always be delivered to `InsertionSerializer.deliver`.**

If this is violated, the serializer will wait forever for a `seq` whose `drain` never arrives, causing deadlock. Therefore:
- `UtteranceProcessor.process` **never throws**; it folds results into `Outcome` (`.formatted` / `.rawFallback` / `.empty`).
- `InsertionSerializer` increments `nextExpected += 1` even for failed or silent utterances → no gaps in sequence, no blocking of subsequent utterances.
- On recording cancellation, `.rawFallback(reason: .cancelled)` or `.empty` must always be delivered (no drops allowed).

---

## Key Components (New Files)

Detailed types and ordering logic are based on the Plan agent design. Only key points are noted here.

- **`Models/Pipeline/Utterance.swift`** — `UtteranceSeq`(Comparable), `RawUtterance`(seq, audioURL, locale, capturedAt), `FormattedChunk`(index, text), `ProcessedUtterance`(seq, Outcome), `ProcessingError`. All `Sendable`.
- **`Pipeline/UtteranceIntake.swift`** (actor) — On recording stop, **immediately assigns a seq** via `submit(audioURL:locale:) -> UtteranceSeq` and yields to `AsyncStream`. The caller can immediately start the next recording.
- **`Pipeline/PipelineCoordinator.swift`** (actor) — Consumes the Intake stream and processes utterances in parallel with a bounded-pump of `maxConcurrentUtterances` (the next is dispatched each time one completes). Routes each utterance to `processor.process` → `serializer.deliver`.
- **`Pipeline/GlobalModelLimiter.swift`** (actor) — Async semaphore across all chunks. Uses `withPermit { ... }` to prevent acquire/release mismatches (always releases via defer). `maxConcurrentModelCalls=1` means fully serial. **Recursive permit acquisition is prohibited** (causes self-deadlock at limit=1).
- **`Pipeline/UtteranceProcessor.swift`** — Processes one utterance: `Transcribe → Chunk split → TaskGroup parallel format (write back to index slots) → join`. **Never throws**; folds into Outcome. If even one chunk cannot be formatted, the entire utterance falls back to the raw transcript (all-or-nothing, to avoid partial mixing).
- **`Pipeline/InsertionSerializer.swift`** (actor) — Receives via `deliver(_:)`, holds in `pending[seq]` buffer. Chains flush as long as `nextExpected` matches (early arrivals are held; when all are ready, inserts in one go). **The heart of the ordering guarantee.**
- **`Services/Chunker.swift`** (actor) — Greedy sentence-boundary packing based on `tokenCount(for:)`. Input budget = `(contextSize - instructionTokens) / (1 + outputSafetyFactor) * safety_factor` (formatting output ≈ input size, so both must fit within 4096). Sentence splitting uses `NLTokenizer(.sentence)` with locale specified (for multi-language support). Hard splits at character count only when a single sentence exceeds the budget. Falls back to character-count approximation when `tokenCount` is unavailable (pre-26.4).
- **`Services/ChunkFormatter.swift`** — Formats one chunk = one `LanguageModelSession` under `limiter.withPermit`. On `exceededContextWindowSize`, retries with re-splitting **serially while holding the permit** (no recursive acquire).
- **`Services/Transcriber.swift`** — `SpeechAnalyzer`/`SpeechTranscriber` (pre-recorded audio + locale). Returns finalized text. Includes timeout.
- **`Insertion/TextInserter.swift`** (actor) — Gets focused element via AX → inserts directly; falls back to clipboard on failure (CGEvent Cmd-V synthesis or pasteboard save + notification).
- **`State/PipelineStatusStore.swift`** (`@MainActor` ObservableObject) — `state: .ready/.recording/.processing(queued:)`, `lastInsertedSeq`, `lastError`. Updated via `await` from each actor (MainActor hops are acceptable since updates are per-utterance). Queue depth = enqueued − inserted.
- **`App/PipelineRuntime.swift`** — Composition Root. `AsyncStream.makeStream()`, wiring all components, launching Coordinator in a `Task`. `Config(maxConcurrentModelCalls, maxConcurrentUtterances, outputSafetyFactor)`.

---

## Multi-Language Design

- **Language model**: `Models/Language/SupportedLanguage.swift` represents the set of languages "available in Speech assets ∩ handleable by Foundation Models." Dynamically computed at launch:
  - Speech-supported locales: queried from `SpeechTranscriber`'s supported locales. Not-yet-installed assets are requested for on-device download via `AssetInventory` (`AssetInstallationRequest`), with progress and completion handled.
  - Available languages = the intersection of the above. The menu distinguishes "Downloaded / Downloadable / Unsupported."
- **Language switching UX (confirmed)**: The popover in `UI/MenuBar/` shows the current language, and a one-click selection from the language list changes `currentLocale`. Recording bakes this `currentLocale` into `RawUtterance.locale` (language is fixed per utterance). The default language is also stored in settings.
- **Formatting prompt**: To scale across languages without writing per-language prompts, use a **language-agnostic template** as the base. Explicitly states "output in the same language as input, never translate," "remove fillers, add punctuation, spoken-to-written style, no summarization, no added information, preserve proper nouns." `Formatting/FormattingPromptFactory.swift` accepts a locale and can inject language-specific overrides if needed (initially: shared template + minor adjustments for Japanese/English only).
- Formatting intensity modes (`raw`/`light`/`standard`) remain in settings as in the initial version (`raw` = formatting OFF for fault isolation).

---

## Retained from the Original Plan (Brief)

- **Permissions**: Microphone / Speech Recognition / Accessibility / Input Monitoring. `PermissionManager` handles initial checks, shortage listing, System Settings navigation, and re-checks.
- **Hotkey**: PTT via `CGEventTap`. keyDown (first press) starts recording / keyUp stops / auto-repeat is ignored. Target key is configurable (default Right Command, etc.). Recording is exclusive (no re-entry).
- **Recording**: `AVAudioEngine` for mono capture, temporary file/buffer, no persistent storage. Max recording duration (initially ~60s, extended from 30s in the initial version to accommodate long utterances).
- **Insertion**: AX direct insertion → clipboard fallback → notification. Insertion mode is configurable (auto/direct/paste).
- **Settings**: `UserDefaults`-based (migrate to SwiftData if it grows). Added stored items: **default language / 2 concurrency knobs / outputSafetyFactor / formatting mode**.
- **Logging**: `OSLog`. Utterance text and formatted text are generally not retained.
- **Privacy**: No network transmission, no persistent audio storage, no external sending.

---

## Recommended Directory Structure

```
vkey/
  App/
    vkeyApp.swift              # Replace with MenuBarExtra
    PipelineRuntime.swift      # Composition Root
  Models/
    Pipeline/Utterance.swift
    Language/SupportedLanguage.swift
    Settings.swift  FormattingMode.swift  InsertionMode.swift  PermissionState.swift
  Pipeline/
    UtteranceIntake.swift  PipelineCoordinator.swift
    GlobalModelLimiter.swift  UtteranceProcessor.swift  InsertionSerializer.swift
  Services/
    Transcriber.swift  Chunker.swift  ChunkFormatter.swift
  Formatting/
    FormattingPromptFactory.swift
  Insertion/
    TextInserter.swift  ClipboardFallback.swift
  Capture/
    HotkeyMonitor.swift  AudioCaptureService.swift
  Permissions/
    PermissionManager.swift  PermissionViewModel.swift
  State/
    PipelineStatusStore.swift
  UI/
    MenuBar/ MenuBarView.swift  LanguagePickerView.swift  StatusIcon.swift
    Settings/ SettingsView.swift  (General/Recording/Language/Formatting/Insertion/Diagnostics)
  Infrastructure/
    Logger.swift  SettingsStore.swift
```

---

## Implementation Phases & Task List

Verify build (xcode MCP) at the end of each phase. For items requiring developer verification, obtain developer approval before committing (AGENTS.md / global CLAUDE.md).

### Phase 1: Skeleton
- [x] Convert `vkeyApp` to `MenuBarExtra` (resident menu bar app), clean up default `ContentView`
- [x] `SettingsStore`(UserDefaults) + `Settings` model + settings screen skeleton
- [x] Introduce `PipelineStatusStore`(@MainActor) and `OSLog`
- [x] Completion criteria: Launch, menu bar display, and settings save work (verified by successful build)

### Phase 2: Permissions and Hotkey
- [x] `PermissionManager` (display/guide/re-check status for Mic/Speech/AX/Input Monitoring)
- [x] `HotkeyMonitor` (CGEventTap, keyDown/up detection, ignore auto-repeat, flagsChanged for modifier keys)
- [x] Completion criteria: Missing permissions shown, key press/release detected (verified by successful build; actual permission grant and key detection require device verification)

### Phase 3: Recording + Intake
- [x] `AudioCaptureService` (AVAudioEngine, temporary storage, no persistence, auto-stop at max duration)
- [x] Connect `UtteranceIntake` (seq assignment + AsyncStream, synchronous seq assignment on MainActor = FIFO guarantee) to recording stop. Next recording available immediately after stop.
- [x] Completion criteria: Recording → `RawUtterance` flows into stream, consecutive recordings accepted (verified by receipt log in provisional consumer + successful build)

### Phase 4: Transcription (Direct Verification for Single Utterance)
- [x] `Transcriber` (SpeechAnalyzer/SpeechTranscriber, locale specified, auto-download assets, timeout, concurrent results collection)
- [x] Log transcript output for 1 utterance in provisional consumer
- [x] Completion criteria: Short utterance becomes a string (verified by successful build; actual recognition accuracy requires device verification)
- Note: Project uses `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`. Service layer is implemented as `actor` or with explicit isolation.

### Phase 5: Chunk Splitting + Formatting
- [x] `Chunker` (contextSize-based input budget, NLTokenizer sentence splitting, hard split, character-type-based approximation)
- [x] `FormattingPromptFactory` (language-agnostic template, explicit prohibition of translation and summarization)
- [x] `GlobalModelLimiter` + `ChunkFormatter` (format under permit, re-split retry on exceeded)
- [x] `UtteranceProcessor` (TaskGroup parallel format + join in index order + Outcome folding, no throws)
- [x] Completion criteria: Long utterances are split and formatted (verified by successful build; formatting quality requires device verification)
- Note: `SystemLanguageModel.contextSize` is a synchronous Int in this SDK. Falls back to raw if model is unavailable.

### Phase 6: Queued Parallel Pipeline + Ordered Insertion
- [x] `PipelineCoordinator` (bounded-pump with `maxConcurrentUtterances`)
- [x] `InsertionSerializer` (ascending seq re-ordering buffer, consumes seq for failures/silence too)
- [x] `TextInserter` (AX direct insertion → clipboard Cmd-V fallback, restore original clipboard)
- [x] All wiring consolidated in `AppCoordinator.startPipeline()` (no separate `PipelineRuntime`, integrated)
- [x] Completion criteria: Pipeline wiring and successful build verified. Ordering behavior in practice requires device verification.

### Phase 7: Multi-language UI
- [x] `LanguageManager` (dynamic computation of Speech `supportedLocales` ∩ FM `supportsLocale`, `installedLocales` for download status, download via AssetInventory)
- [x] Quick language switch in menu bar (current language display + one-click change + show undownloaded + auto-download on selection)
- [x] Language section in settings (list, selection, download status, individual download, refresh)
- [x] Completion criteria: Language selection UI and successful build verified. Recording → formatting → insertion on device requires verification.

### Phase 8: Productionization & Tuning
- [x] Error messages and notifications (fallback/failure notifications via UserNotifications, ON/OFF in settings)
- [x] Login item (`SMAppService` linked to launchAtLogin), Copy Last Result, model availability display
- [x] Settings refinement (restart note for concurrency), icon states, logging cleanup
- [ ] Benchmark the 2 concurrency knobs → finalize default values (**not done, requires device verification**; adjustable via UI)
- [x] Completion criteria: Productionization elements implemented and successful build. Daily-use stability requires device verification.

---

## Implementation Status (as of 2026-06-09)

All 8 phases have been implemented, with successful xcode MCP builds and zero warnings confirmed for each phase.
Following that, the UI, formatting, language management, and i18n were significantly revised based on developer feedback from physical device testing (see "Post-Implementation Revisions" below).
**For the current overall state of the app, see [`docs/app_overview.md`](../app_overview.md)** (this plan remains as the primary source for design intent and pipeline details).
Some aspects of audio, model, insertion, and permissions still require device verification (see "Device Verification TODO").

### Post-Implementation Revisions (Device Feedback Applied, 2026-06-09)

Through device testing, the following changes were made from what was described in this plan. The design core (3-layer ordering + 2-knob parallel pipeline) is unchanged.

- **Menu bar converted to AppKit**: `MenuBarExtra` had trouble re-rendering labels on ObservableObject changes, making icon animation difficult, so it is now managed directly via `NSStatusItem` (`UI/MenuBar/StatusItemController.swift`) with a Timer for blinking. States: Idle=`mic` / Recording=`mic.fill` blinking / Processing=`ellipsis.bubble` blinking.
- **Settings window converted to custom NSWindow**: On macOS, opening a SwiftUI Settings scene from AppKit fails ("Please use SettingsLink"), so `SettingsWindowController` manages it directly. Uses `orderFrontRegardless` + `moveToActiveSpace` to reliably bring it to the front.
- **Settings tabs consolidated to two**: Only "General" (combining permissions/launch/hotkey/formatting/custom instructions) and "Language." Diagnostics tab removed.
- **Permission UI shown only when permissions are missing**: Missing permissions are shown prominently at the top of the "General" tab only when any are lacking; hidden when all are granted.
- **Items removed from user settings (converted to internal constants)**: Max recording duration (internal 300s safety limit), `outputSafetyFactor` (internal 1.15), and the 2 concurrency knobs (no UI; loaded at launch with defaults 1/2).
- **Insertion mode fixed to auto**: Removed user selection (always AX direct insertion → clipboard on failure). `InsertionMode` enum remains internally.
- **Replaced notifications with alerts**: Removed `UserNotifications`; only shows an `NSAlert` **when insertion completely fails** (to guide clipboard save). No notification when clipboard-based insertion succeeds.
- **Improved formatting prompt**: Framed as a "transcript editor" with strong prohibitions on responding to input, translating, and summarizing. Added a rule to append `?` for questions in languages that use it.
- **Custom formatting instructions (new feature)**: A free-text field of up to 200 characters under the formatting mode. Injected into the prompt while preserving safety rules (no translation, response, or summarization). Also reflected in chunk token calculations.
- **Formatting mode now shows description + examples.**
- **Enhanced language management**: "Remove" button (`AssetInventory.release`) for downloaded languages. Remove button is hidden for the system language since it cannot be deleted by the OS. When the selected language is removed, automatically reverts to the system language. Default language moved to the top of the list.
- **Hotkey converted to free-input style**: Recorder-style where pressing any single key registers it (modifier keys captured via flagsChanged).
- **i18n support**: UI internationalized via String Catalog (`vkey/Localizable.xcstrings`). **Development language = English, with Japanese translations included.** SwiftUI uses `Text` literals; AppKit/model computed properties use `String(localized:)`. Added `ja` to `knownRegions`.

### Device Verification TODO (Build Only Verified; Device Testing Required)
- [ ] Permission flow: grant Microphone/Speech Recognition/Accessibility/Input Monitoring on first launch → each feature works
- [ ] Hotkey: recording while holding Right Command (default), finalizing on release (flagsChanged detection for modifier keys)
- [ ] Recording → transcription: short Japanese/English utterances correctly converted to text
- [ ] Language asset download: selecting an undownloaded language triggers download via AssetInventory
- [ ] Formatting: filler removal and punctuation insertion work; no translation, summarization, or alteration occurs
- [ ] Token splitting: long text (3000–5000 characters) splits and formats without exceededContextWindowSize
- [ ] Ordering guarantee: consecutive utterances A→B→C are inserted in FIFO × chunk order
- [ ] Insertion: AX direct insertion in TextEdit/Notes/Safari/Slack; clipboard fallback on failure
- [ ] Concurrency benchmark: measure `maxConcurrentModelCalls` at 1↔3 and finalize default values
- [ ] Notification, login item, and Copy Last Result behavior

## Verification Methods

- **Build**: Verify the build passes with the xcode MCP tool at each phase.
- **Ordering guarantee (Phase 6 key)**: "Speak a long utterance A, then immediately follow with short utterances B/C consecutively," and visually verify in TextEdit that the insertion result is in the order A→B→C with each utterance's chunks correctly concatenated in order. Verify that changing `maxConcurrentModelCalls` and `maxConcurrentUtterances` between 1↔3 does not break ordering.
- **Token splitting**: Speak a long text exceeding 4096 tokens (e.g., 3000–5000 characters) in one go and verify it splits and formats without producing `exceededContextWindowSize`. Also verify boundary cases (text that just barely fits / barely does not fit in one chunk).
- **Multi-language**: For Japanese, English, and 1–2 other languages, verify: asset download → recording → formatting (no translation, original language preserved) → insertion.
- **Insertion targets**: AX direct insertion and fallback in TextEdit / Notes / Safari input fields / Slack / VS Code.
- **Error isolation**: Verify that intentionally injecting a silent utterance, very short recording, or formatting failure does not block subsequent insertion order.
- **Edge cases**: Recording under 0.3s / near max duration / non-editable focus / password field / immediately after switching apps.

---

## Risks and Mitigations

- **Model parallelization may have no real effect** → Default `maxConcurrentModelCalls=1` and measure in Phase 8. Concurrency is independent of ordering guarantees, so even if parallelization has no effect, the architecture is unchanged (the value of queuing = accepting consecutive recordings remains).
- **`tokenCount` estimation drift causing context overflow** → Two layers of protection: Chunker safety factor + ChunkFormatter re-split retry.
- **AX implementation differences (Electron/browser/custom UI)** → Prepare clipboard fallback early, make insertion mode configurable.
- **Formatting too aggressive (summarization/alteration)** → Strongly prohibit summarization/information addition/translation in the prompt; use `raw`/`light` modes to isolate issues.
- **Multi-language asset download failure/size** → Show download status explicitly in UI; exclude unsupported languages from choices.

---

## Confirmed Design Decisions & Default Values

- Language switching: Quick switch in menu bar (finalized before recording; locale baked in per utterance).
- Supported languages: All major languages (dynamically computed). Formatting prompts start with a language-agnostic template + minor adjustments for Japanese/English only.
- Concurrency defaults: `maxConcurrentModelCalls=1`, `maxConcurrentUtterances=2`, `outputSafetyFactor=1.15` (tuned in Phase 8).
- Fallback policy: If even one chunk cannot be formatted, insert the entire utterance as raw transcript (all-or-nothing).
- History storage, dictionary, learning, per-app rules, and waveform UI are out of scope (same as initial version).

---

## Appendix: Post-Confirmation Operations (AGENTS.md)

Once this plan is approved, before starting implementation, follow the AGENTS.md procedure:
1. Rename this file to `docs/plans/001-local-voice-input-pipeline.md` (sequential number + descriptive name)
2. Add to the reference materials index in AGENTS.md
3. (The task list above is already embedded in this file)
4. Commit these changes together (after developer confirmation)
