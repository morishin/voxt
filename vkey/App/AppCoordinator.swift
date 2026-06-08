//
//  AppCoordinator.swift
//  vkey
//
//  アプリ全体の配線役。権限・ホットキー・録音・取り込み・（後フェーズで）整形と挿入を束ねる。
//

import Foundation
import Combine
import CoreGraphics
import FoundationModels
import OSLog

@MainActor
final class AppCoordinator: ObservableObject {

    let settings: SettingsStore
    let status: PipelineStatusStore
    let permissions: PermissionManager

    private let hotkey: HotkeyMonitor
    private let capture = AudioCaptureService()
    private let intake: UtteranceIntake
    private let utteranceStream: AsyncStream<RawUtterance>
    private let transcriber = Transcriber()

    private var consumerTask: Task<Void, Never>?
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

    /// 起動時に呼ぶ。権限確認・ホットキー監視・発話 consumer を開始する。
    func start() {
        permissions.refresh()
        hotkey.start()
        startConsumer()
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
    }

    private func updateHotKey(keyCode: Int) {
        hotkey.stop()
        hotkey.keyCode = CGKeyCode(keyCode)
        hotkey.start()
    }

    // MARK: - Recording

    private func startRecording() {
        guard !capture.recording else { return }
        do {
            _ = try capture.start(maxSeconds: settings.maxRecordingSeconds)
            status.recordingStarted()
        } catch {
            status.reportError("録音開始に失敗しました: \(error)")
        }
    }

    private func stopRecordingAndSubmit() {
        let url = capture.stop()
        status.recordingStopped()
        guard let url else { return }
        let locale = Locale(identifier: settings.defaultLanguageIdentifier)
        intake.submit(audioURL: url, locale: locale)
    }

    // MARK: - Consumer（Phase 6 で PipelineCoordinator に置き換える暫定実装）

    private func startConsumer() {
        let maxModelCalls = settings.maxConcurrentModelCalls
        consumerTask = Task { [utteranceStream, transcriber, settings] in
            // 処理スタックを 1 度だけ構築する（GlobalModelLimiter は全発話で共有）。
            let contextSize = SystemLanguageModel.default.contextSize
            let chunker = Chunker(contextSize: contextSize)
            let limiter = GlobalModelLimiter(maxConcurrentModelCalls: maxModelCalls)
            let formatter = ChunkFormatter(limiter: limiter, chunker: chunker)
            let processor = UtteranceProcessor(transcriber: transcriber, chunker: chunker, formatter: formatter)

            for await u in utteranceStream {
                Log.pipeline.info("received utterance seq=\(u.seq.raw) locale=\(u.locale.identifier, privacy: .public)")
                let config = await Self.makeConfig(from: settings)
                let result = await processor.process(u, config: config)
                Self.logOutcome(result)
                // Phase 6 で順序保証挿入を行う。現状は処理結果のログまで。
                try? FileManager.default.removeItem(at: u.audioURL)
            }
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

    private static func logOutcome(_ result: ProcessedUtterance) {
        switch result.outcome {
        case .formatted(let text):
            Log.formatting.info("formatted seq=\(result.seq.raw): \(text, privacy: .private)")
        case .rawFallback(let text, let reason):
            Log.formatting.info("raw fallback seq=\(result.seq.raw) (\(reason.message, privacy: .public)): \(text, privacy: .private)")
        case .empty:
            Log.formatting.info("empty utterance seq=\(result.seq.raw)")
        }
    }
}
