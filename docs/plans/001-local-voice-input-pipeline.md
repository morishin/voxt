# vkey — ローカル音声入力アプリ 実装プラン（多言語 + キューイング並列パイプライン）

## Context（なぜ作るか）

`~/Downloads/keyvoice_local_only_implementation_plan.md`（ChatGPT 作成の初版プラン）をベースに、
Apple 純正フレームワークのみで完全ローカル動作する macOS 26+ 向け Push-to-talk 音声入力アプリを作る。
押している間だけ録音 →（Speech で）文字起こし →（Foundation Models で）忠実な整文 → フォーカス中アプリへ挿入する。

初版プランに対し、開発者から以下の本質的な要件追加・修正が入った。本プランはこれらを設計の中心に据えて作り直したもの。

1. **最初から多言語対応**。日本語固定ではなく、ユーザーが言語を選べること。録音前に言語を確定する必要がある（後述）。
2. **トークン上限対策の処理分割**。Apple の on-device モデルは **1 セッション 4096 トークン上限**（入力+指示+出力すべて含む）。長い発話は文字起こし後にチャンク分割してから整形する必要がある。
   - 参考: RevComm 記事（https://tech.revcomm.co.jp/foundation-models-proto）。4096 上限・Map-Reduce 分割・セッション都度生成・実測 5000字≈10秒/15000字≈30-60秒 などの知見。本アプリは「要約」ではなく「整文」なので Reduce 不要・Map（チャンク並列整形）→ index 順結合で足りる。
3. **キューイング機構**。①1 発話の処理中でも次の録音を受け付け、順に処理する。②1 発話内の複数チャンクは直列でなく**並列**で整形してスループットを上げる。③ただし最終的な挿入は**発話の FIFO 順 × 発話内のチャンク順**を厳密に守る。

### 確定した技術前提（リサーチ済み）
- Foundation Models: 1 セッション **4096 トークン**上限。超過時 `LanguageModelSession.GenerationError.exceededContextWindowSize` を throw。macOS **26.4** で `SystemLanguageModel.contextSize` プロパティと `tokenCount(for:)` メソッドが追加され、事前にトークン数を計測できる。
- on-device モデルは**単一のシステム共有リソース**。複数セッションを並列実行しても実 HW で直列化される可能性があり、並列化の実効果は不確実 → **並列度を設定可能（チューナブル）にして実測で決める**。
- Speech（macOS 26 の `SpeechAnalyzer`/`SpeechTranscriber`）は**録音前に locale 確定が必要**。音声からの言語自動判定は構造上できない → 言語は事前選択方式。
- 配布は Developer ID + notarization 前提。Mac App Store / Sandbox は考慮しない。

### 開発者が確定した方針（質問への回答）
- **言語の切替 UX**: メニューバー（ポップオーバー）で現在の言語を表示し、ワンクリックで素早く切替。録音前に選ぶ。
- **初期対応言語**: 主要言語すべて（Speech 資産が入手可能 & Foundation Models が扱える言語）を最初から選択肢に。整形プロンプトは言語非依存テンプレート（後述）で N 言語をスケールさせ、品質検証はライトに。

### 現状
- `vkey` / `vkey.xcodeproj` は新規 SwiftUI スキャフォールド済み（`vkeyApp.swift` + `ContentView.swift` のデフォルトのみ）。`docs/` は空。ゼロからの実装。
- ビルド確認は MCP の **xcode** ツールで行う（AGENTS.md）。

---

## アーキテクチャ全体像

3 つの順序付けレイヤを**完全に分離**するのが設計の核心。これにより「並列で速く処理しつつ、挿入だけ厳密 FIFO」を両立する。

- **発話の受付順** = `seq`（録音停止時に採番した瞬間に FIFO 確定）
- **発話内チャンク順** = `chunkIndex`（並列整形しても index スロットへ書き戻して復元）
- **挿入順** = `InsertionSerializer` が `seq` 昇順を厳密に待つ re-ordering バッファ

```
[PTT録音(排他)] ──停止──▶ seq採番(即) ──▶ AsyncStream
   │                                          │
   └─ すぐ次の録音受付OK         ┌────────────▼──────────────┐
                                 │ PipelineCoordinator        │
                                 │  発話レベル並列度を         │
                                 │  bounded-pump で制御        │
                                 │  (maxConcurrentUtterances) │
                                 └────────────┬──────────────┘
                              ┌───────────────▼────────────────┐
                              │ UtteranceProcessor (発話ごと)   │
                              │ 1. Transcribe (Speech)          │
                              │ 2. Chunk split (tokenCount)     │
                              │ 3. TaskGroup 並列整形 ───────┐  │
                              │ 4. index 順 join             │  │
                              └──────────────┬───────────────┘  │
                                             │   ┌──────────────▼──────────────┐
                                             │   │ GlobalModelLimiter           │
                                             │   │ 全発話横断のモデル並列度制御 │
                                             │   │ (maxConcurrentModelCalls)    │
                                             │   └──────────────────────────────┘
                              ┌──────────────▼───────────────┐
                              │ InsertionSerializer (actor)   │
                              │ seq 昇順に厳密直列化して挿入  │
                              └──────────────┬───────────────┘
                                  ┌──────────▼──────────┐
                                  │ TextInserter         │
                                  │ AX 挿入 → CB fallback │
                                  └──────────────────────┘
```

### 並列度は 2 ノブ（互いに直交、どちらも順序保証に影響しない）

| ノブ | 制御対象 | 目的 |
|---|---|---|
| `maxConcurrentModelCalls`（GlobalModelLimiter） | 全発話横断のモデル同時呼び出し総数 | on-device モデルが実 HW で並列化されるか検証。`1`=直列ベースライン |
| `maxConcurrentUtterances`（PipelineCoordinator） | 同時処理中の発話数（段オーバーラップ） | Speech↔Model↔Insertion のパイプライン化（発話 n の整形中に n+1 を先行文字起こし） |

両ノブとも順序保証から独立しているため、どう振っても挿入結果は常に「発話 FIFO × チャンク順」で確定する。初期値は `maxConcurrentModelCalls=1`, `maxConcurrentUtterances=2`、実測で調整。

### 順序保証を支える不変条件（最重要）
> **採番された全 `seq` は、成功・失敗・無音・キャンセルいずれでも必ず `InsertionSerializer.deliver` される。**

これが破れると `drain` が来ない seq を永久に待ちデッドロックする。だから:
- `UtteranceProcessor.process` は**決して throw せず**、結果を `Outcome`（`.formatted` / `.rawFallback` / `.empty`）に畳む。
- `InsertionSerializer` は失敗・無音発話でも `nextExpected += 1` する → 順序の穴が空かず後続をブロックしない。
- 録音キャンセル時も `.rawFallback(reason: .cancelled)` か `.empty` を必ず deliver（取りこぼし禁止）。

---

## 主要コンポーネント（新規作成ファイル）

詳細な型・順序保証ロジックは Plan エージェント設計に基づく。要点のみ記載。

- **`Models/Pipeline/Utterance.swift`** — `UtteranceSeq`(Comparable), `RawUtterance`(seq, audioURL, locale, capturedAt), `FormattedChunk`(index,text), `ProcessedUtterance`(seq, Outcome), `ProcessingError`。すべて `Sendable`。
- **`Pipeline/UtteranceIntake.swift`** (actor) — 録音停止時に `submit(audioURL:locale:) -> UtteranceSeq` で**即採番**して `AsyncStream` に yield。呼び出し側はすぐ次の録音へ。
- **`Pipeline/PipelineCoordinator.swift`** (actor) — Intake ストリームを消費し、`maxConcurrentUtterances` の bounded-pump（1 つ完了するたび次を投入）で発話を並列処理。各発話を `processor.process` → `serializer.deliver` へ。
- **`Pipeline/GlobalModelLimiter.swift`** (actor) — 全チャンク横断の async セマフォ。`withPermit { ... }` で acquire/release ペアミス防止（defer で必ず release）。`maxConcurrentModelCalls=1` で完全直列。**permit の再帰取得は禁止**（limit=1 で自己デッドロック）。
- **`Pipeline/UtteranceProcessor.swift`** — 1 発話を `Transcribe → Chunk split → TaskGroup 並列整形（index スロットへ書き戻し）→ join`。**throw せず** Outcome に畳む。1 チャンクでも整形不能なら発話全体を生 transcript に fallback（部分混在を避ける all-or-nothing）。
- **`Pipeline/InsertionSerializer.swift`** (actor) — `deliver(_:)` で受け取り、`pending[seq]` バッファに保持。`nextExpected` と一致する限り連鎖 flush（早着は保留、揃ったら一気に挿入）。**順序保証の心臓部**。
- **`Services/Chunker.swift`** (actor) — `tokenCount(for:)` ベースの文境界グリーディパッキング。input budget = `(contextSize - instructionTokens) / (1 + outputSafetyFactor) * 安全係数`（整文は出力≈入力なので両方を 4096 に収める）。文分割は `NLTokenizer(.sentence)` を locale 指定で（多言語対応）。単文が budget 超のみ文字数で hard split。`tokenCount` 不可（26.4 未満）時は概算 fallback。
- **`Services/ChunkFormatter.swift`** — `limiter.withPermit` 下で 1 チャンク=1 `LanguageModelSession` 整形。`exceededContextWindowSize` 時は**permit 保持のまま直列で**再分割リトライ（再帰 acquire しない）。
- **`Services/Transcriber.swift`** — `SpeechAnalyzer`/`SpeechTranscriber`（録音済み音声＋locale）。確定テキストを返す。タイムアウト付き。
- **`Insertion/TextInserter.swift`** (actor) — AX で focused element 取得→直接挿入、失敗時クリップボード fallback（CGEvent Cmd-V 合成 or ペボード退避＋通知）。
- **`State/PipelineStatusStore.swift`** (`@MainActor` ObservableObject) — `state: .ready/.recording/.processing(queued:)`、`lastInsertedSeq`、`lastError`。各 actor から `await` 更新（更新頻度は発話単位なので MainActor hop は許容）。キュー残数 = enqueued − inserted。
- **`App/PipelineRuntime.swift`** — Composition Root。`AsyncStream.makeStream()`、各コンポーネント配線、Coordinator を `Task` で起動。`Config(maxConcurrentModelCalls, maxConcurrentUtterances, outputSafetyFactor)`。

---

## 多言語対応の設計

- **言語モデル**: `Models/Language/SupportedLanguage.swift` に「Speech 資産が入手可能 ∩ Foundation Models が扱える」言語集合を表現。起動時に動的算出する:
  - Speech 対応 locale: `SpeechTranscriber` の supported locales を照会。未インストール資産は `AssetInventory`（`AssetInstallationRequest`）でオンデバイス DL を要求し、進捗・完了を扱う。
  - 利用可能言語 = 上記の交差。メニューに「DL 済み / DL 可能 / 未対応」を区別表示。
- **言語切替 UX（確定方針）**: `UI/MenuBar/` のポップオーバーに現在の言語を表示し、言語リストからワンクリックで `currentLocale` を変更。録音はこの `currentLocale` を `RawUtterance.locale` に焼き付ける（発話ごとに言語が固定）。設定に既定言語も保持。
- **整形プロンプト**: 言語ごとに手書きせずスケールさせるため、**言語非依存テンプレート**を基本にする。「入力と同じ言語で出力し、決して翻訳しない」「フィラー除去・句読点補完・話し言葉→書き言葉・要約禁止・情報追加禁止・固有名詞維持」を明示。`Formatting/FormattingPromptFactory.swift` で locale を受け取り、必要なら言語別オーバーライドを差し込める構造に（初期は共通テンプレ + 日本語/英語のみ微調整）。
- 整形強度モード（`raw`/`light`/`standard`）は初版どおり設定に残す（`raw`=整形 OFF で障害切り分け）。

---

## 従来プラン踏襲分（簡潔に）

- **権限**: Microphone / Speech Recognition / Accessibility / Input Monitoring。`PermissionManager` で初回チェック・不足一覧・システム設定誘導・再チェック。
- **ホットキー**: `CGEventTap` で PTT。keyDown 初回で録音開始 / keyUp で停止 / auto-repeat 無視。対象キー設定可能（初期 Right Command など）。録音は排他（再入禁止）。
- **録音**: `AVAudioEngine` でモノラル収録、一時ファイル/バッファ、永続保存しない。最大録音秒数（初期 60 秒程度、長文も想定して初版の 30 秒より延長）。
- **挿入**: AX 直接挿入 → クリップボード fallback → 通知。挿入方式は設定（auto/direct/paste）。
- **設定**: `UserDefaults` ベース（増えたら SwiftData）。保存項目に**既定言語 / 並列度 2 ノブ / outputSafetyFactor / 整形モード** を追加。
- **ログ**: `OSLog`。発話本文・変換本文は原則残さない。
- **プライバシー**: ネットワーク送信なし・音声永続保存なし・外部送信なし。

---

## 推奨ディレクトリ構成

```
vkey/
  App/
    vkeyApp.swift              # MenuBarExtra に置換
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

## 実装フェーズ & タスクリスト

各フェーズ末でビルド確認（xcode MCP）。動作確認を要するものは開発者の OK を取ってからコミット（AGENTS.md / グローバル CLAUDE.md）。

### Phase 1: 骨組み
- [x] `vkeyApp` を `MenuBarExtra` 化（常駐メニューバーアプリ）、デフォルト `ContentView` 整理
- [x] `SettingsStore`(UserDefaults) + `Settings` モデル + 設定画面スケルトン
- [x] `PipelineStatusStore`(@MainActor) と `OSLog` 導入
- [x] 完了条件: 起動・メニューバー表示・設定保存ができる（ビルド成功で確認）

### Phase 2: 権限とホットキー
- [x] `PermissionManager`（Mic/Speech/AX/Input Monitoring の状態表示・誘導・再チェック）
- [x] `HotkeyMonitor`（CGEventTap, keyDown/up 検出, repeat 無視, 修飾キーは flagsChanged 対応）
- [x] 完了条件: 権限不足を表示、指定キー押下/解放が取れる（ビルド成功で確認。実機での権限付与・キー検出は要動作確認）

### Phase 3: 録音 + 取り込み
- [x] `AudioCaptureService`（AVAudioEngine, 一時保存, 永続なし, 最大秒数で自動停止）
- [x] `UtteranceIntake`(seq 採番 + AsyncStream, MainActor で同期採番=FIFO保証) を録音停止に接続。停止後すぐ次録音可能
- [x] 完了条件: 録音→`RawUtterance` がストリームに流れ、連続録音を受け付ける（暫定 consumer で受領ログ・ビルド成功で確認）

### Phase 4: 文字起こし（単一発話の直結確認）
- [ ] `Transcriber`（SpeechAnalyzer/SpeechTranscriber, locale 指定, タイムアウト）
- [ ] まず `maxConcurrentUtterances=1` で 1 発話→transcript を確認
- [ ] 完了条件: 短文発話が文字列になる

### Phase 5: チャンク分割 + 整形
- [ ] `Chunker`（tokenCount/contextSize ベース input budget、NLTokenizer 文分割、hard split、概算 fallback）
- [ ] `FormattingPromptFactory`（言語非依存テンプレ、翻訳禁止・要約禁止明示）
- [ ] `GlobalModelLimiter` + `ChunkFormatter`（permit 下整形、exceeded 時の再分割リトライ）
- [ ] `UtteranceProcessor`（TaskGroup 並列整形 + index 順 join + Outcome 畳み込み、throw しない）
- [ ] 完了条件: 長文発話が分割整形され、フィラー除去・句読点補完を含む自然な整文になる

### Phase 6: キュー並列パイプライン + 順序保証挿入
- [ ] `PipelineCoordinator`（bounded-pump で `maxConcurrentUtterances`）
- [ ] `InsertionSerializer`（seq 昇順 re-ordering バッファ、失敗/無音も seq 消費）
- [ ] `TextInserter`（AX 挿入 → クリップボード fallback）
- [ ] `PipelineRuntime` で全配線
- [ ] 完了条件: 処理中に連続録音しても、挿入が発話 FIFO × チャンク順を厳守する

### Phase 7: 多言語 UI
- [ ] `SupportedLanguage`（Speech supported ∩ FM 対応の動的算出、AssetInventory DL）
- [ ] メニューバーの言語クイック切替（現在言語表示 + ワンクリック変更 + DL 状態表示）
- [ ] 設定の Language セクション（既定言語）
- [ ] 完了条件: 主要言語を選んで録音・整形・挿入が通る

### Phase 8: 実用化・チューニング
- [ ] 並列度 2 ノブの実測ベンチ（直列 vs 並列、`maxConcurrentModelCalls` の実効果判定）→ 既定値確定
- [ ] エラー文言・通知・設定画面整理・アイコン状態・ログ整理
- [ ] 完了条件: 日常利用でストレスが少なく、クラッシュしない

---

## 検証方法

- **ビルド**: 各フェーズで xcode MCP ツールでビルドが通ることを確認。
- **順序保証（Phase 6 の要）**: 「長め発話 A を喋り終えた直後に短い発話 B/C を連続録音」し、挿入結果が A→B→C の順かつ各発話内のチャンクが順序通りに連結されることを TextEdit で目視確認。`maxConcurrentModelCalls` や `maxConcurrentUtterances` を 1↔3 で変えても順序が崩れないこと。
- **トークン分割**: 4096 を超える長文（例 3000〜5000 字）を一気に喋り、`exceededContextWindowSize` を出さず分割整形されることを確認。境界（ちょうど 1 チャンクに収まる/収まらない長さ）も確認。
- **多言語**: 日本語・英語・他 1〜2 言語で、資産 DL → 録音 → 整形（翻訳されない・原言語維持）→ 挿入を確認。
- **挿入先**: TextEdit / Notes / Safari 入力欄 / Slack / VS Code 系で AX 直接挿入と失敗時 fallback。
- **エラー独立性**: わざと無音発話・極短録音・整形失敗を挟んでも後続の挿入順がブロックされないこと。
- **境界**: 0.3 秒未満録音 / 最大秒数付近 / 非編集フォーカス / パスワード欄 / アプリ切替直後。

---

## リスクと対策

- **モデル並列化の実効果が無い可能性** → `maxConcurrentModelCalls=1` を既定にし Phase 8 で実測。並列度は順序保証と独立なので、効果が無くてもアーキテクチャはそのまま（キューイング＝連続録音受付の価値は残る）。
- **`tokenCount` 推定ずれで context 超過** → Chunker の安全係数 + ChunkFormatter の再分割リトライの二段構え。
- **AX 実装差（Electron/ブラウザ/独自 UI）** → 早期にクリップボード fallback を用意、挿入方式を設定化。
- **整形が強すぎる（要約・改変）** → プロンプトで要約/情報追加/翻訳を強く禁止、`raw`/`light` モードで切り分け。
- **多言語の資産 DL 失敗・容量** → DL 状態を UI で明示、未対応言語は選択肢から除外。

---

## 確定済みの設計判断・既定値

- 言語切替: メニューバーのクイック切替（録音前に確定、発話ごとに locale を焼き付け）。
- 対応言語: 主要言語すべて（動的算出）。整形プロンプトは言語非依存テンプレート + 日英のみ微調整から開始。
- 並列度既定: `maxConcurrentModelCalls=1`, `maxConcurrentUtterances=2`, `outputSafetyFactor=1.15`（Phase 8 で調整）。
- fallback 方針: 1 チャンクでも整形不能なら発話全体を生 transcript で挿入（all-or-nothing）。
- 履歴保存・辞書・学習・アプリ別ルール・波形 UI は対象外（初版踏襲）。

---

## 補足: 確定後の運用（AGENTS.md）

このプランが承認されたら、実装着手前に AGENTS.md の手順を実施する:
1. 本ファイルを `docs/plans/001-local-voice-input-pipeline.md`（連番 + 内容名）にリネーム
2. AGENTS.md の参考資料索引に追記
3. （上記のタスクリストは本ファイルに内蔵済み）
4. これらをまとめてコミット（開発者の確認後）
