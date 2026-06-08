# Voxt — App Overview (Current State)

A **fully local** push-to-talk voice input utility for macOS 26+. Using only Apple's native frameworks,
it records audio while a hotkey is held down → transcribes (Speech) → formats (Foundation Models) → inserts into the focused app.
No network transmission, no persistent storage of audio or text.

For the primary design source (pipeline, ordering guarantees, and concurrency details), see [`plans/001-local-voice-input-pipeline.md`](plans/001-local-voice-input-pipeline.md).
This document is stock information summarizing the overview of the "currently running app."

## App Form
- Menu bar resident app (`.accessory`, no Dock icon). The menu bar is managed by AppKit `NSStatusItem`.
- Icon state: The brand logo (`MenuBarIcon` template image) is displayed in all states, distinguished by blink speed. Idle = static / Recording = slow blink (period 1.4s) / Processing = fast blink (period 0.45s).
- App icon: `Voxt/Voxt.icon` in Icon Composer format (build setting `ASSETCATALOG_COMPILER_APPICON_NAME = Voxt`).

## Menu Bar Menu
- Status label (Ready / Recording… / Processing (n))
- Warning when Apple Intelligence is disabled (indicating text will be inserted without formatting)
- Language: current language → switch to a downloaded language with one click via submenu / "Other Languages…" opens the Language tab in Settings
- Copy Last Result
- Settings… (⌘,) / Quit Voxt (⌘Q)

## Settings (3 Tabs)
- **General**
  - Permissions (only the missing ones are shown prominently at the top when any are lacking; hidden when all are granted)
  - Launch at Login (`SMAppService`)
  - Hotkey (recorder-style: press any single key to register; push-to-talk)
  - Formatting mode (Off / Light / Standard) + mode description and examples
  - Custom formatting instructions (optional, max 200 characters; shown when mode is not Off)
- **Language**
  - Supported languages = dynamically calculated as the intersection of Speech-supported languages and Foundation Models-capable languages
  - Downloaded languages are selectable with a "Remove" button (not shown for the system language, as it is OS-managed and cannot be deleted)
  - Not-yet-downloaded languages are grayed out with a "Download" button (with progress spinner)
  - The default (currently selected) language is shown at the top of the list
- **About**
  - App icon, app name, version (`CFBundleShortVersionString`)
  - Update check (compared against the latest GitHub Releases version; see [`release.md`](release.md) for details)
  - Author (`morishin`) / Donate button (Buy me a coffee), both linking to GitHub Sponsors

## Key Behaviors
- **Language is determined before recording** (automatic language detection from audio is structurally impossible). The locale is baked in per utterance.
- **Long text is split into chunks** for formatting (to handle the 4096-token limit of the on-device model). Chunks within a single utterance are formatted in parallel and joined in index order.
- **Insertion strictly follows "utterance FIFO × chunk order."** The next recording is accepted even while processing is in progress, and insertions proceed in order.
- **Insertion**: Direct insertion via AX → falls back to typing via CGEvent Unicode input when that fails (both are **clipboard-free**). Only when neither is available does it fall back to the clipboard and show an `NSAlert` prompting manual paste.
- **Formatting**: Framed as a "transcript editor," with responses to input, translations, and summaries explicitly prohibited. Custom instructions are injected while preserving these safety rules.

## Internationalization (i18n)
- String Catalog (`Voxt/Localizable.xcstrings`). **Development language = English, with Japanese translations included.**
- SwiftUI uses `Text` literals; AppKit/model computed properties use `String(localized:)`.
- Display language follows the system language (per-app language override is also available in System Settings).

## Internal Defaults Not Exposed to Users
- Max recording duration: 300s (safety limit in case of missed keyUp events)
- `outputSafetyFactor`: 1.15
- Concurrency: `maxConcurrentModelCalls=1` / `maxConcurrentUtterances=2` (no UI)
- Insertion mode: always auto (direct insertion → paste fallback)

## Permissions
Microphone / Speech Recognition / Accessibility / Input Monitoring. `PermissionManager` handles status checks, requests, navigation to System Settings, and re-checking.
If Accessibility is not granted at launch, `CGRequestPostEventAccess()` is called to request "event posting" permission.
(The generic AppKit `AXIsProcessTrustedWithOptions` prompt may not appear for accessory apps, so the same API path used for actual insertion is used to trigger the dialog and register the app in System Settings.)

## Privacy
Audio and text are processed entirely locally. No persistent storage of audio or text, no external transmission. Recordings are stored as temporary files and deleted after processing.
The only external communication is the **update check in the About tab** (reference to GitHub Releases only; no personal data is sent).
