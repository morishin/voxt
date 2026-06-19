# vkey → Voxt リリース準備 & 機能追加プラン

## Context

アプリ名を **Voxt** に変更し、macOS App Store 外で配布する（ノータライズ済み .zip を GitHub Releases `github.com/morishin/voxt` で公開）。ソースコード・ファイル名・フォルダ名から "vkey" を完全に除去する。Settings に About タブ（アップデートチェック + GitHub Sponsors リンク）を追加する。

---

## 変更の依存関係

```
ファイル/フォルダのリネーム (vkey/ → Voxt/ など)
    ↓
Voxt.xcodeproj/project.pbxproj (パス・ターゲット名・Bundle ID)
    ↓
Localizable.xcstrings (vkey → Voxt + About 新規キー)
    ↓
StatusItemController.swift (accessibilityDescription)
    ↓
Voxt/Voxt.entitlements (network.client 追加)
    ↓
Voxt/Services/UpdateChecker.swift [新規]
    ↓
Voxt/UI/Settings/AboutView.swift [新規]
    ↓
SettingsNavigation.swift (.about ケース)
SettingsView.swift (About タブ追加)
    ↓
.github/workflows/release.yml [新規]
```

---

## 1. ファイル・フォルダのリネーム（ファイルシステム）

```
vkey.xcodeproj/          → Voxt.xcodeproj/
vkey/                    → Voxt/
vkey/vkeyApp.swift       → Voxt/VoxtApp.swift
vkey/vkey.entitlements   → Voxt/Voxt.entitlements
```

その他 `Voxt/` 以下のファイルはリネーム不要（内部の Swift ファイル名は識別子ではない）。

---

## 2. `Voxt.xcodeproj/project.pbxproj`

このプロジェクトは `PBXFileSystemSynchronizedRootGroup` を使っており、フォルダ内のファイルは自動認識される。フォルダリネーム後に更新が必要な箇所：

| 箇所 | 旧値 | 新値 |
|------|------|------|
| PBXFileReference `path` | `vkey.app` | `Voxt.app` |
| PBXFileSystemSynchronizedRootGroup `path` | `vkey` | `Voxt` |
| PBXNativeTarget `name` | `vkey` | `Voxt` |
| PBXNativeTarget `productName` | `vkey` | `Voxt` |
| Build configuration list コメント | `"vkey"` | `"Voxt"` |
| Debug/Release `CODE_SIGN_ENTITLEMENTS` | `vkey/vkey.entitlements` | `Voxt/Voxt.entitlements` |
| Debug/Release `PRODUCT_BUNDLE_IDENTIFIER` | `me.morishin.vkey` | `me.morishin.voxt` |
| `INFOPLIST_KEY_NSMicrophoneUsageDescription` | "vkey は…" | "Voxt は…" |
| `INFOPLIST_KEY_NSSpeechRecognitionUsageDescription` | "vkey は…" | "Voxt は…" |

**注意:** 現在 `PRODUCT_NAME = "$(TARGET_NAME)"` となっているため、ターゲット名を `Voxt` にすれば製品名も自動で `Voxt` になる（明示的な `PRODUCT_NAME` 追加は不要）。`ENABLE_HARDENED_RUNTIME = YES` と `CODE_SIGN_STYLE = Automatic` は既に設定済みで変更不要。

---

## 3. `Voxt/Localizable.xcstrings`

既存キーの更新（en/ja 両方）:
| 旧 | 新 en | 新 ja |
|---|---|---|
| `"Quit vkey"` | `"Quit Voxt"` | `"Voxt を終了"` |
| `"vkey needs permission to work"` | `"Voxt needs permission to work"` | `"Voxt を使うには権限の許可が必要です"` |

新規追加キー（About タブ用）:
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
- `"Quit vkey"` → `"Quit Voxt"`（xcstrings 更新が反映される）

---

## 5. `Voxt/Voxt.entitlements`

```xml
<key>com.apple.security.network.client</key>
<true/>
```
を追加（GitHub API アクセスに必要）。

---

## 6. `Voxt/Services/UpdateChecker.swift` [新規]

GitHub releases/latest への HEAD リクエストでリダイレクト先 URL の末尾（タグ）からバージョンを抽出し、現在の `CFBundleShortVersionString` と比較する。

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

## 7. `Voxt/UI/Settings/AboutView.swift` [新規]

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
    case about        // 追加
}
```

---

## 9. `Voxt/UI/Settings/SettingsView.swift`

`TabView` に3つ目のタブを追加:
```swift
AboutView()
    .tabItem { Label("About", systemImage: "info.circle") }
    .tag(SettingsTab.about)
```

---

## 10. `.github/workflows/release.yml` [新規]

**前提条件・注意:**
このプロジェクトは `MACOSX_DEPLOYMENT_TARGET = 26.4`（macOS 26 Tahoe、Xcode 26）を使用しており、GitHub の標準 `macos-latest` ランナー（Xcode 16 系）ではビルドできない。GitHub が公式に macOS 26 ランナーを提供するまでは**セルフホストランナー**（Xcode 26 がインストール済みの手元の Mac）が必要。

トリガー: `v*` タグ push

```yaml
name: Release
on:
  push:
    tags: ['v*']

jobs:
  release:
    runs-on: self-hosted   # Xcode 26 + macOS 26 の Mac が必要
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

**必要な GitHub Secrets:**
- `DEVELOPER_CERTIFICATE` (base64 エンコード済み Developer ID Application .p12)
- `CERTIFICATE_PASSWORD`
- `APPLE_ID` / `APP_SPECIFIC_PASSWORD` / `TEAM_ID`

**`ExportOptions.plist`**（リポジトリ root に配置）:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>manual</string>
</dict></plist>
```

---

## 11. メニューバーアイコン（後回し）

画像ファイルが未用意のため `"mic"` SF Symbol のままにする。`Voxt/Assets.xcassets/MenuBarIcon.imageset/` 追加と `StatusItemController.swift` の `.ready` 分岐変更は画像が用意でき次第実施する。

---

## 作業順序

1. ファイル・フォルダのリネーム（`vkey/` → `Voxt/`、`vkey.xcodeproj/` → `Voxt.xcodeproj/`、`vkeyApp.swift` → `VoxtApp.swift`、`vkey.entitlements` → `Voxt.entitlements`）
2. `Voxt.xcodeproj/project.pbxproj` — パス・ターゲット名・Bundle ID・Plist 文字列の更新
3. `Voxt/Voxt.entitlements` — `network.client` 追加
4. `Voxt/Localizable.xcstrings` — vkey→Voxt 置換 + About キー追加
5. `Voxt/UI/MenuBar/StatusItemController.swift` — accessibilityDescription 変更
6. `Voxt/Services/UpdateChecker.swift` — 新規作成
7. `Voxt/UI/Settings/AboutView.swift` — 新規作成
8. `Voxt/State/SettingsNavigation.swift` — `.about` ケース追加
9. `Voxt/UI/Settings/SettingsView.swift` — About タブ追加
10. `.github/workflows/release.yml` + `ExportOptions.plist` — 新規作成

---

## 検証方法

1. Xcode MCP でビルドが通ること
2. Settings ウィンドウに「About」タブが表示され、バージョン文字列・アップデートチェック・Sponsors リンクが正しく機能すること
3. メニューバーの「Quit Voxt」が正しく表示されること
4. ダークモード切り替え時に Settings ウィンドウが追従すること（SwiftUI 自動対応）
5. `v1.0` タグを push → GitHub Actions（セルフホストランナー）が起動 → ノータライズ済み `Voxt-stapled.zip` が Releases に添付されること
