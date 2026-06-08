# vkey → Voxt Release Preparation & Feature Addition Plan

## Context

Rename the app to **Voxt** and distribute it outside the macOS App Store (publishing a notarized .zip to GitHub Releases at `github.com/morishin/voxt`). Completely remove all references to "vkey" from source code, file names, and folder names. Add an About tab to Settings (with update check + GitHub Sponsors link).

---

## Dependency Order of Changes

```
File/folder rename (vkey/ → Voxt/ etc.)
    ↓
Voxt.xcodeproj/project.pbxproj (paths, target name, Bundle ID)
    ↓
Localizable.xcstrings (vkey → Voxt + new About keys)
    ↓
StatusItemController.swift (accessibilityDescription)
    ↓
Voxt/Voxt.entitlements (add network.client)
    ↓
Voxt/Services/UpdateChecker.swift [new]
    ↓
Voxt/UI/Settings/AboutView.swift [new]
    ↓
SettingsNavigation.swift (.about case)
SettingsView.swift (add About tab)
    ↓
.github/workflows/release.yml [new]
```

---

## 1. File & Folder Rename (Filesystem)

```
vkey.xcodeproj/          → Voxt.xcodeproj/
vkey/                    → Voxt/
vkey/vkeyApp.swift       → Voxt/VoxtApp.swift
vkey/vkey.entitlements   → Voxt/Voxt.entitlements
```

Other files under `Voxt/` do not need to be renamed (Swift file names are not identifiers).

---

## 2. `Voxt.xcodeproj/project.pbxproj`

This project uses `PBXFileSystemSynchronizedRootGroup`, so files in the folder are automatically recognized. The following locations need to be updated after the folder rename:

| Location | Old Value | New Value |
|------|------|------|
| PBXFileReference `path` | `vkey.app` | `Voxt.app` |
| PBXFileSystemSynchronizedRootGroup `path` | `vkey` | `Voxt` |
| PBXNativeTarget `name` | `vkey` | `Voxt` |
| PBXNativeTarget `productName` | `vkey` | `Voxt` |
| Build configuration list comment | `"vkey"` | `"Voxt"` |
| Debug/Release `CODE_SIGN_ENTITLEMENTS` | `vkey/vkey.entitlements` | `Voxt/Voxt.entitlements` |
| Debug/Release `PRODUCT_BUNDLE_IDENTIFIER` | `me.morishin.vkey` | `me.morishin.voxt` |
| `INFOPLIST_KEY_NSMicrophoneUsageDescription` | "vkey needs…" | "Voxt needs…" |
| `INFOPLIST_KEY_NSSpeechRecognitionUsageDescription` | "vkey needs…" | "Voxt needs…" |

**Note:** Currently `PRODUCT_NAME = "$(TARGET_NAME)"`, so renaming the target to `Voxt` will automatically make the product name `Voxt` (no need to add an explicit `PRODUCT_NAME`). `ENABLE_HARDENED_RUNTIME = YES` and `CODE_SIGN_STYLE = Automatic` are already configured and do not need to change.

---

## 3. `Voxt/Localizable.xcstrings`

Update existing keys (both en and ja):
| Old | New en | New ja |
|---|---|---|
| `"Quit vkey"` | `"Quit Voxt"` | `"Voxt を終了"` |
| `"vkey needs permission to work"` | `"Voxt needs permission to work"` | `"Voxt を使うには権限の許可が必要です"` |

New keys to add (for the About tab):
```json
"About":               { ja: "このアプリについて" },
"Version %@":          { ja: "バージョン %@" },
"Check for Updates":   { ja: "アップデートを確認" },
"Checking…":           { ja: "確認中…" },
"Up to date":          { ja: "最新版です" },
"Update Available":    { ja: "アップデートあり" },
"Author":              { ja: "作者" },
"Buy me a coffee":     { ja: "Buy me a coffee" }
```

---

## 4. `Voxt/UI/MenuBar/StatusItemController.swift`

- Line 85: `accessibilityDescription: "vkey"` → `"Voxt"`
- `"Quit vkey"` → `"Quit Voxt"` (reflected by xcstrings update)

---

## 5. `Voxt/Voxt.entitlements`

Add:
```xml
<key>com.apple.security.network.client</key>
<true/>
```
(Required for GitHub API access.)

---

## 6. `Voxt/Services/UpdateChecker.swift` [new]

Extracts the version from the end of the redirect URL (the tag) via a HEAD request to GitHub releases/latest, and compares it with the current `CFBundleShortVersionString`.

```swift
@MainActor
final class UpdateChecker: ObservableObject {
    enum Status { case idle, checking, upToDate, available(URL) }
    @Published var status: Status = .idle

    func check() async {
        status = .checking
        let latestURL = URL(string: "https://github.com/morishin/voxt/releases/latest")!
        var req = URLRequest(url: latestURL)
        req.httpMethod = "HEAD"
        guard let (_, response) = try? await URLSession.shared.data(for: req),
              let finalURL = (response as? HTTPURLResponse)?.url else {
            status = .idle; return
        }
        let remote = finalURL.lastPathComponent.trimmingCharacters(in: .init(charactersIn: "v"))
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        if remote.compare(current, options: .numeric) == .orderedDescending {
            status = .available(finalURL)
        } else {
            status = .upToDate
        }
    }
}
```

---

## 7. `Voxt/UI/Settings/AboutView.swift` [new]

```swift
struct AboutView: View {
    @StateObject private var checker = UpdateChecker()
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 80, height: 80)
            Text("Voxt").font(.title.bold())
            Text(String(format: String(localized: "Version %@"), version))
                .foregroundStyle(.secondary)
            Divider()
            switch checker.status {
            case .idle, .upToDate:
                Button(String(localized: "Check for Updates")) { Task { await checker.check() } }
            case .checking:
                ProgressView(String(localized: "Checking…"))
            case .available(let url):
                Link(String(localized: "Update Available"), destination: url)
                    .buttonStyle(.borderedProminent)
            }
            Divider()
            LabeledContent(String(localized: "Author")) {
                Link("Shintaro Morikawa", destination: URL(string: "https://github.com/morishin")!)
            }
            Link(destination: URL(string: "https://github.com/sponsors/morishin?frequency=one-time")!) {
                Label(String(localized: "Buy me a coffee"), systemImage: "cup.and.saucer.fill")
            }
            .buttonStyle(.bordered)
        }
        .padding(32)
        .task { await checker.check() }
    }
}
```

---

## 8. `Voxt/State/SettingsNavigation.swift`

```swift
enum SettingsTab: String, Hashable, CaseIterable {
    case general
    case language
    case about        // added
}
```

---

## 9. `Voxt/UI/Settings/SettingsView.swift`

Add a third tab to the `TabView`:
```swift
AboutView()
    .tabItem { Label("About", systemImage: "info.circle") }
    .tag(SettingsTab.about)
```

---

## 10. `.github/workflows/release.yml` [new]

**Prerequisites and notes:**
This project uses `MACOSX_DEPLOYMENT_TARGET = 26.4` (macOS 26 Tahoe, Xcode 26), and cannot be built on GitHub's standard `macos-latest` runner (Xcode 16). Until GitHub officially provides macOS 26 runners, a **self-hosted runner** (your own Mac with Xcode 26 installed) is required.

Trigger: `v*` tag push

```yaml
name: Release
on:
  push:
    tags: ['v*']

jobs:
  release:
    runs-on: self-hosted   # Requires a Mac with Xcode 26 + macOS 26
    steps:
      - uses: actions/checkout@v4

      - name: Import certificate
        run: |
          echo "$DEVELOPER_CERTIFICATE" | base64 --decode > cert.p12
          security create-keychain -p "" build.keychain
          security import cert.p12 -k build.keychain -P "$CERTIFICATE_PASSWORD" -T /usr/bin/codesign
          security list-keychains -s build.keychain
          security set-key-partition-list -S apple-tool:,apple: -s -k "" build.keychain
        env:
          DEVELOPER_CERTIFICATE: ${{ secrets.DEVELOPER_CERTIFICATE }}
          CERTIFICATE_PASSWORD: ${{ secrets.CERTIFICATE_PASSWORD }}

      - name: Archive
        run: |
          xcodebuild archive \
            -project Voxt.xcodeproj \
            -scheme Voxt \
            -configuration Release \
            -archivePath "$RUNNER_TEMP/Voxt.xcarchive" \
            CODE_SIGN_STYLE=Manual \
            CODE_SIGN_IDENTITY="Developer ID Application"

      - name: Export
        run: |
          xcodebuild -exportArchive \
            -archivePath "$RUNNER_TEMP/Voxt.xcarchive" \
            -exportPath "$RUNNER_TEMP/export" \
            -exportOptionsPlist ExportOptions.plist

      - name: Zip, Notarize & Staple
        run: |
          ditto -c -k --keepParent "$RUNNER_TEMP/export/Voxt.app" "$RUNNER_TEMP/Voxt.zip"
          xcrun notarytool submit "$RUNNER_TEMP/Voxt.zip" \
            --apple-id "$APPLE_ID" \
            --password "$APP_SPECIFIC_PASSWORD" \
            --team-id "$TEAM_ID" \
            --wait
          xcrun stapler staple "$RUNNER_TEMP/export/Voxt.app"
          ditto -c -k --keepParent "$RUNNER_TEMP/export/Voxt.app" "$RUNNER_TEMP/Voxt-stapled.zip"
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APP_SPECIFIC_PASSWORD: ${{ secrets.APP_SPECIFIC_PASSWORD }}
          TEAM_ID: ${{ secrets.TEAM_ID }}

      - name: Create GitHub Release
        run: gh release create "${{ github.ref_name }}" "$RUNNER_TEMP/Voxt-stapled.zip" --generate-notes
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**Required GitHub Secrets:**
- `DEVELOPER_CERTIFICATE` (base64-encoded Developer ID Application .p12)
- `CERTIFICATE_PASSWORD`
- `APPLE_ID` / `APP_SPECIFIC_PASSWORD` / `TEAM_ID`

**`ExportOptions.plist`** (placed at repository root):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>manual</string>
</dict></plist>
```

---

## 11. Menu Bar Icon (Deferred)

The image file is not yet prepared, so the `"mic"` SF Symbol is used as-is. Adding `Voxt/Assets.xcassets/MenuBarIcon.imageset/` and changing the `.ready` branch in `StatusItemController.swift` will be done once the image is ready.

---

## Work Order

1. File/folder rename (`vkey/` → `Voxt/`, `vkey.xcodeproj/` → `Voxt.xcodeproj/`, `vkeyApp.swift` → `VoxtApp.swift`, `vkey.entitlements` → `Voxt.entitlements`)
2. `Voxt.xcodeproj/project.pbxproj` — update paths, target name, Bundle ID, and Plist strings
3. `Voxt/Voxt.entitlements` — add `network.client`
4. `Voxt/Localizable.xcstrings` — replace vkey→Voxt + add About keys
5. `Voxt/UI/MenuBar/StatusItemController.swift` — update accessibilityDescription
6. `Voxt/Services/UpdateChecker.swift` — create new file
7. `Voxt/UI/Settings/AboutView.swift` — create new file
8. `Voxt/State/SettingsNavigation.swift` — add `.about` case
9. `Voxt/UI/Settings/SettingsView.swift` — add About tab
10. `.github/workflows/release.yml` + `ExportOptions.plist` — create new files

---

## Verification

1. Build passes via Xcode MCP
2. Settings window shows the "About" tab with the version string, update check, and Sponsors link working correctly
3. "Quit Voxt" in the menu bar displays correctly
4. Settings window follows dark mode switching (SwiftUI handles this automatically)
5. Push a `v1.0` tag → GitHub Actions (self-hosted runner) starts → notarized `Voxt-stapled.zip` is attached to Releases
