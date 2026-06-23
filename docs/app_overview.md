# Voxt — アプリ概要（現状）

macOS 26+ 向けの**完全ローカル**な Push-to-talk 音声入力ユーティリティ。Apple 純正フレームワークのみで、
ホットキーを押している間だけ録音 → 文字起こし（Speech）→ 整形（Foundation Models）→ フォーカス中アプリへ挿入する。
ネットワーク送信・音声/本文の永続保存は行わない。

設計の一次資料（パイプライン・順序保証・並列度の詳細）は [`plans/001-local-voice-input-pipeline.md`](plans/001-local-voice-input-pipeline.md) を参照。
本書は「いま動いているアプリ」の概観をまとめたストック情報。

## 形態
- メニューバー常駐アプリ（`.accessory`、Dock アイコンなし）。メニューバーは AppKit `NSStatusItem` で管理。
- アイコン状態: 全状態でブランドロゴ（`MenuBarIcon` テンプレート画像）を表示し、明滅速度で区別する。待機 = 静止 / 録音中 = ゆっくり明滅（周期 1.4秒）/ 処理中 = かなり速く明滅（周期 0.45秒）。
- アプリアイコンは Icon Composer 形式の `Voxt/Voxt.icon`（ビルド設定 `ASSETCATALOG_COMPILER_APPICON_NAME = Voxt`）。

## メニューバーのメニュー
- 状態ラベル（Ready / Recording… / Processing (n)）
- Apple Intelligence 無効時の警告（整形なしで挿入する旨）
- Language: 現在の言語 → サブメニューで DL 済み言語をワンクリック切替 / 「他の言語…」で設定の言語タブへ
- 最後の結果をコピー
- 設定…（⌘,）/ Voxt を終了（⌘Q）

## 設定画面（3 タブ）
- **一般**
  - 権限（不足がある時だけ最上部に目立つ形で不足分のみ表示。全許可なら非表示）
  - ログイン時に起動（`SMAppService`）
  - ホットキー（任意のキーを 1 つ押して登録するレコーダー方式。Push-to-talk）
  - 整形モード（Off / Light / Standard）＋ モード説明・例
  - カスタム整形指示（任意・最大 200 字。Off 以外で表示）
- **言語**
  - 対応言語 = Speech が対応 ∩ Foundation Models が扱える言語を動的算出
  - DL 済みは選択可・「削除」ボタン（システム言語は OS 管理で消せないため非表示）
  - 未 DL は淡色・「ダウンロード」ボタン（進捗スピナー）
  - デフォルト（選択中）言語をリスト先頭に表示
- **About**
  - アプリアイコン・アプリ名・バージョン（`CFBundleShortVersionString`）
  - アップデート確認（GitHub Releases の最新版と比較。詳細は [`release.md`](release.md)）
  - 作者（`morishin`）/ ドネートボタン（Buy me a coffee）。いずれも GitHub Sponsors へのリンク

## 動作の要点
- **言語は録音前に確定**（音声からの言語自動判定は構造上不可）。発話ごとに locale を焼き付ける。
- **長文はチャンク分割**して整形（on-device モデルの 4096 トークン上限対策）。1 発話内のチャンクは並列整形し index 順で結合。
- **挿入は厳密に「発話 FIFO × チャンク順」**。処理中でも次の録音を受け付け、順に挿入。
- **挿入**: AX で直接挿入 → 失敗時は CGEvent の Unicode 直接入力でタイプ（いずれも**クリップボード非経由**）。両方使えない時のみクリップボードへ退避し `NSAlert` で手動貼り付けを案内。
- **整形**: 「transcript editor」として枠付けし、入力への回答・翻訳・要約を禁止。カスタム指示はこの安全ルールを保ったまま追加適用。

## 多言語対応（i18n）
- String Catalog（`Voxt/Localizable.xcstrings`）。**開発言語=英語、日本語訳を収録**。
- SwiftUI は `Text` リテラル、AppKit/モデルの計算プロパティは `String(localized:)`。
- 表示言語はシステム言語に追従（システム設定のアプリ別言語で個別切替も可能）。

## ユーザーに露出しない内部既定値
- 最大録音秒数: 300s（keyUp 取りこぼし時の安全上限）
- `outputSafetyFactor`: 1.15
- 並列度: `maxConcurrentModelCalls=1` / `maxConcurrentUtterances=2`（UI なし）
- 挿入方式: 常に auto（直接挿入 → ペースト fallback）

## 権限
マイク / 音声認識 / アクセシビリティ / 入力監視。`PermissionManager` が状態確認・要求・システム設定誘導・再チェックを担う。
アクセシビリティは起動時に未許可なら `CGRequestPostEventAccess()` で「イベント投函」権限を要求する。
（AppKit 汎用の `AXIsProcessTrustedWithOptions` プロンプトはアクセサリアプリだと出ないことがあるため、実際の挿入で使う API と同じ経路で要求し、ダイアログ表示とシステム設定一覧への登録を促す。）

## プライバシー
音声・本文は完全ローカル処理。音声/本文の永続保存なし・外部送信なし。録音は一時ファイルで処理後に削除。
唯一の外部通信は **About タブのアップデート確認**（GitHub Releases への参照のみ。個人データは送らない）。
