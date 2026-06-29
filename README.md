<img width="2652" height="1152" alt="voxt-hero" src="https://github.com/user-attachments/assets/27881878-2b38-49d6-a93f-9fd8f4789f5a" />

# Voxt

Push-to-talk voice input for macOS. Hold a key, speak, release — Voxt transcribes and formats your words with on-device AI, then types them wherever your cursor is. Fully local. No cloud.

[voxt.morishin.me](https://voxt.morishin.me)

## Features

- **Offline** — all processing happens on your Mac; nothing is ever sent to a server
- **Push-to-talk** — hold any key to record, release to insert
- **On-device AI** — Apple Speech recognition + Foundation Models (Apple Intelligence) for transcription and formatting
- **Custom instructions** — tell the formatter how you want your text shaped
- **Multi-language** — Japanese and English speech recognition

## Requirements

- macOS 26 or later
- Apple Intelligence (on-device Foundation Models)

## Installation

Download the latest `.zip` from [GitHub Releases](https://github.com/morishin/voxt/releases/latest), unzip, and move `Voxt.app` to `/Applications`.

On first launch, Voxt will ask for:
- **Microphone** — to record your voice
- **Speech Recognition** — to transcribe audio on-device
- **Accessibility** — to type text into other apps
- **Input Monitoring** — to detect your push-to-talk hotkey

## Usage

1. Open Voxt — it lives in the menu bar, not the Dock
2. Click the menu bar icon → **Settings** to choose your hotkey and formatting preferences
3. Hold your hotkey, speak, release — the formatted text appears at your cursor

## Building from source

```bash
git clone https://github.com/morishin/voxt.git
open Voxt.xcodeproj
```

Build and run the **Voxt** scheme in Xcode 26 or later. No external dependencies.

For release builds, see [docs/release.md](docs/release.md).

## License

Voxt is released under the [GNU General Public License v3.0](LICENSE).

Copyright © 2026 Shintaro Morikawa
