# リリース & 配布ガイド（開発者向け）

Voxt は **App Store 外配布**。Developer ID で署名し Apple のノータライズを通した `.zip` を
**GitHub Releases（`morishin/voxt`）** で配布する。アプリは GitHub の最新リリースを見て自動でアップデートの有無を表示する。

## 配布の全体像

```
開発者が v* タグを push
        │
        ▼
GitHub Actions (macos-26 ホストランナー / .github/workflows/release.yml)
  1. Developer ID 証明書を一時キーチェーンへ取り込み
  2. xcodebuild archive（Release・手動署名・--timestamp・Hardened Runtime）
  3. xcodebuild -exportArchive（ExportOptions.plist / developer-id）
  4. xcrun notarytool submit --wait（Apple にノータライズ申請）
  5. xcrun stapler staple（チケットを .app に添付）
  6. gh release create で Voxt.zip を Releases に添付
        │
        ▼
ユーザーが Releases から Voxt.zip をダウンロード
        │
        ▼
アプリ内（設定 → About）が releases/latest を見て更新の有無を表示
```

セルフホストランナーは使わない。GitHub ホストの `macos-26`（Xcode 26 入り）で完結する。

## 前提

- Apple Developer Program 加入（Team ID: `4GERXBURZN`）
- **Developer ID Application** 証明書 + 秘密鍵
- ローカル開発・手動ビルドには Xcode 26 / macOS 26 が必要（Apple Intelligence / FoundationModels のため）

## GitHub Secrets（`morishin/voxt` の Settings → Secrets and variables → Actions に登録済み）

リリースワークフローは以下の 6 つのリポジトリシークレットを使う。フォークからの PR には渡らない仕様なので public リポジトリでも安全。

| シークレット名 | 内容 | 作り方 |
|---|---|---|
| `BUILD_CERTIFICATE_BASE64` | Developer ID Application 証明書(.p12)を base64 化した文字列 | キーチェーンアクセスの「自分の証明書」から証明書を `.p12` で書き出し → `base64 -i cert.p12 \| pbcopy` |
| `P12_PASSWORD` | 上記 `.p12` 書き出し時に設定したパスワード | `.p12` 書き出しダイアログで設定 |
| `KEYCHAIN_PASSWORD` | CI 上で作る一時キーチェーンのパスワード | 任意の文字列でよい |
| `APPLE_ID` | ノータライズに使う Apple ID（メールアドレス） | 開発者アカウントのメール |
| `APPLE_APP_PASSWORD` | ノータライズ用の **App 用パスワード**（通常のログインパスワードではない） | [appleid.apple.com](https://appleid.apple.com) → サインインとセキュリティ → App用パスワード で発行 |
| `APPLE_TEAM_ID` | Team ID（`4GERXBURZN`） | Apple Developer の Membership ページ |

> Team ID 自体は秘匿情報ではなく `project.pbxproj` の `DEVELOPMENT_TEAM` にも書かれているが、
> ワークフローからの参照を一元化するためシークレットとしても持たせている。

## リリース手順

1. `main` を最新化し、リリースに含めたい変更がマージ済みであることを確認する。
2. バージョンタグを打って push する（タグ名がそのままアプリのバージョンになる）。
   ```sh
   git switch main && git pull
   git tag v1.0
   git push origin v1.0
   ```
3. GitHub の **Actions** タブで `Release` ワークフローの進行を確認する（ノータライズ待ちで数分かかる）。
4. 完了後、**Releases** に `Voxt.zip` が添付されていることを確認する。

### バージョン番号について
- ワークフローが `MARKETING_VERSION` をタグ名（`v1.2` → `1.2`）に上書きするため、`project.pbxproj` を手で更新する必要はない。
- これによりアプリの `CFBundleShortVersionString` がリリースタグと一致し、アップデートチェックが正しく機能する。
- `CURRENT_PROJECT_VERSION`（ビルド番号）は Actions の実行番号を使う。

## アプリ内アップデートチェックの仕組み

- 実装: `Voxt/Services/UpdateChecker.swift`
- `https://github.com/morishin/voxt/releases/latest` に HEAD リクエストを送り、リダイレクト先 URL の末尾（`/releases/tag/vX.Y`）からバージョンを取り出す。
- それを現在の `CFBundleShortVersionString` と `.numeric` 比較し、新しければ設定 → About に「Update Available」を表示してリリースページへ誘導する。
- **参照先リポジトリを変えたら** `UpdateChecker.swift` の `latestReleaseURL` を更新すること。
- 外部通信のため `Voxt/Voxt.entitlements` に `com.apple.security.network.client` を付与している。

## ローカルで手動リリースする場合（CI を使わないとき）

CI が使えない・緊急時のフォールバック。Xcode 26 のある Mac で実行する。

```sh
xcodebuild archive -project Voxt.xcodeproj -scheme Voxt -configuration Release \
  -archivePath /tmp/Voxt.xcarchive -destination "generic/platform=macOS" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM=4GERXBURZN OTHER_CODE_SIGN_FLAGS="--timestamp"

xcodebuild -exportArchive -archivePath /tmp/Voxt.xcarchive \
  -exportPath /tmp/export -exportOptionsPlist ExportOptions.plist

ditto -c -k --keepParent /tmp/export/Voxt.app /tmp/Voxt.zip
xcrun notarytool submit /tmp/Voxt.zip --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_PASSWORD" --team-id 4GERXBURZN --wait
xcrun stapler staple /tmp/export/Voxt.app
ditto -c -k --keepParent /tmp/export/Voxt.app /tmp/Voxt.zip   # staple 後に再 zip

gh release create v1.0 /tmp/Voxt.zip --title v1.0 --generate-notes
```

## トラブルシュート

- **署名で失敗する**: 証明書の有効期限切れ、または「自分の証明書」に Developer ID Application の秘密鍵が無い可能性。`security find-identity -v -p codesigning` で確認。
- **ノータライズで `Invalid` になる**: ログを取得して原因を見る。
  ```sh
  xcrun notarytool log <submission-id> --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" --team-id 4GERXBURZN
  ```
  よくある原因: Hardened Runtime 無効、secure timestamp 無し、署名対象に未署名バイナリが含まれる、など。本プロジェクトは `ENABLE_HARDENED_RUNTIME=YES` と `--timestamp` を設定済み。
- **`macos-26` ランナーが見つからない**: GitHub のランナーイメージ提供状況を確認（[actions/runner-images](https://github.com/actions/runner-images)）。提供ラベルが変わった場合は `release.yml` の `runs-on` を更新する。
- **アプリが「最新版です」のまま更新を検知しない**: Releases にタグ（`vX.Y`）形式のリリースがあるか、`UpdateChecker.swift` の参照先が正しいかを確認する。
