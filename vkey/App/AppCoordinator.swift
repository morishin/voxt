//
//  AppCoordinator.swift
//  vkey
//
//  アプリ全体の配線役。権限・ホットキー・録音・取り込み・（後フェーズで）整形と挿入を束ねる。
//

import Foundation
import Combine
import CoreGraphics
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
        consumerTask = Task { [utteranceStream] in
            for await u in utteranceStream {
                Log.pipeline.info("received utterance seq=\(u.seq.raw) locale=\(u.locale.identifier, privacy: .public)")
                // Phase 4 以降で文字起こし・整形・挿入を行う。
                // 現状は受領のみ。一時音声ファイルはここで削除しておく。
                try? FileManager.default.removeItem(at: u.audioURL)
            }
        }
    }
}
