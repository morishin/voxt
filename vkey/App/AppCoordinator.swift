//
//  AppCoordinator.swift
//  vkey
//
//  アプリ全体の配線役。権限・ホットキー・録音・取り込み・（後フェーズで）整形と挿入を束ねる。
//

import Foundation
import Combine
import CoreGraphics
import AppKit
import FoundationModels
import ServiceManagement
import OSLog

@MainActor
final class AppCoordinator: ObservableObject {

    let settings: SettingsStore
    let status: PipelineStatusStore
    let permissions: PermissionManager
    let languages = LanguageManager()
    let notifier = Notifier()

    private let hotkey: HotkeyMonitor
    private let capture = AudioCaptureService()
    private let intake: UtteranceIntake
    private let utteranceStream: AsyncStream<RawUtterance>
    private let transcriber = Transcriber()

    private var pipelineTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(settings: SettingsStore, status: PipelineStatusStore) {
        self.settings = settings
        self.status = status
        self.permissions = PermissionManager()
        self.hotkey = HotkeyMonitor(keyCode: CGKeyCode(settings.hotKeyKeyCode))

        let (stream, continuation) = AsyncStream<RawUtterance>.makeStream()
        self.utteranceStream = stream
        self.intake = UtteranceIntake(continuation: continuation)

        configureHotkey()
        configureCapture()
        observeSettings()
    }

    /// 起動時に呼ぶ。権限確認・ホットキー監視・処理パイプラインを開始する。
    func start() {
        permissions.refresh()
        hotkey.start()
        status.modelAvailable = SystemLanguageModel.default.isAvailable
        applyLaunchAtLogin(settings.launchAtLogin)
        startPipeline()
        Task {
            await languages.refresh()
            if settings.showNotifications { await notifier.requestAuthorization() }
        }
    }

    /// 直近に挿入したテキストをクリップボードへコピーする（メニューの Last Result 用）。
    func copyLastResult() {
        guard let text = status.lastResultText, !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Hotkey

    private func configureHotkey() {
        hotkey.onPress = { [weak self] in
            MainActor.assumeIsolated { self?.startRecording() }
        }
        hotkey.onRelease = { [weak self] in
            MainActor.assumeIsolated { self?.stopRecordingAndSubmit() }
        }
    }

    private func configureCapture() {
        capture.onMaxDurationReached = { [weak self] in
            MainActor.assumeIsolated { self?.stopRecordingAndSubmit() }
        }
    }

    private func observeSettings() {
        settings.$hotKeyKeyCode
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] newCode in
                self?.updateHotKey(keyCode: newCode)
            }
            .store(in: &cancellables)

        settings.$launchAtLogin
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] enabled in
                self?.applyLaunchAtLogin(enabled)
            }
            .store(in: &cancellables)
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("failed to update login item: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func updateHotKey(keyCode: Int) {
        hotkey.stop()
        hotkey.keyCode = CGKeyCode(keyCode)
        hotkey.start()
    }

    // MARK: - Recording

    /// この秒数未満の録音は誤タップとみなして破棄する。
    private let minRecordingSeconds: TimeInterval = 0.3
    private var recordingStartedAt: Date?

    private func startRecording() {
        guard !capture.recording else { return }
        do {
            _ = try capture.start(maxSeconds: settings.maxRecordingSeconds)
            recordingStartedAt = Date()
            status.recordingStarted()
        } catch {
            status.reportError("録音開始に失敗しました: \(error)")
        }
    }

    private func stopRecordingAndSubmit() {
        let url = capture.stop()
        let elapsed = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? .infinity
        recordingStartedAt = nil
        status.recordingStopped()
        guard let url else { return }

        // 短すぎる録音（誤タップ）は破棄し、無駄な文字起こし・処理フラッシュを避ける。
        if elapsed < minRecordingSeconds {
            Log.capture.info("discarding too-short recording (\(elapsed, format: .fixed(precision: 2))s)")
            try? FileManager.default.removeItem(at: url)
            return
        }

        let locale = Locale(identifier: settings.defaultLanguageIdentifier)
        intake.submit(audioURL: url, locale: locale)
        // 採番した発話をキュー残数に反映する（挿入完了で減算される）。
        status.enqueued()
    }

    // MARK: - Pipeline

    private func startPipeline() {
        let maxModelCalls = settings.maxConcurrentModelCalls
        let maxUtterances = settings.maxConcurrentUtterances
        let status = self.status
        let notifier = self.notifier

        pipelineTask = Task { [utteranceStream, transcriber, settings] in
            // 処理スタックを 1 度だけ構築する（GlobalModelLimiter は全発話で共有）。
            let contextSize = SystemLanguageModel.default.contextSize
            let chunker = Chunker(contextSize: contextSize)
            let limiter = GlobalModelLimiter(maxConcurrentModelCalls: maxModelCalls)
            let formatter = ChunkFormatter(limiter: limiter, chunker: chunker)
            let processor = UtteranceProcessor(transcriber: transcriber, chunker: chunker, formatter: formatter)

            let inserter = TextInserter()
            let serializer = InsertionSerializer(
                inserter: inserter,
                modeProvider: { await MainActor.run { settings.insertionMode } },
                onInserted: { seq, outcome, text in
                    await status.inserted(seq: seq.raw, text: text.isEmpty ? nil : text)
                    let showNotif = await MainActor.run { settings.showNotifications }
                    guard showNotif else { return }
                    switch outcome {
                    case .pasted:
                        await notifier.notify(title: "vkey", body: "直接挿入できなかったため、クリップボード経由で貼り付けました。")
                    case .failed:
                        await notifier.notify(title: "vkey", body: "テキストを挿入できませんでした。内容はクリップボードに保存しました。")
                    case .directInserted, .none:
                        break
                    }
                }
            )
            let coordinator = PipelineCoordinator(
                processor: processor,
                serializer: serializer,
                configProvider: { await Self.makeConfig(from: settings) }
            )

            await coordinator.run(stream: utteranceStream, maxConcurrentUtterances: maxUtterances)
        }
    }

    /// MainActor の設定から処理設定スナップショットを作る。モデル非対応時は raw に倒す。
    private static func makeConfig(from settings: SettingsStore) async -> ProcessingConfig {
        await MainActor.run {
            let modelAvailable = SystemLanguageModel.default.isAvailable
            let mode = modelAvailable ? settings.formattingMode : .raw
            return ProcessingConfig(formattingMode: mode, outputSafetyFactor: settings.outputSafetyFactor)
        }
    }
}
