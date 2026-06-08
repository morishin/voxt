//
//  AppCoordinator.swift
//  vkey
//
//  アプリ全体の配線役。権限・ホットキー・（後フェーズで）録音とパイプラインを束ねる。
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
    private var cancellables: Set<AnyCancellable> = []

    init(settings: SettingsStore, status: PipelineStatusStore) {
        self.settings = settings
        self.status = status
        self.permissions = PermissionManager()
        self.hotkey = HotkeyMonitor(keyCode: CGKeyCode(settings.hotKeyKeyCode))

        configureHotkey()
        observeSettings()
    }

    /// 起動時に呼ぶ。権限確認とホットキー監視を開始する。
    func start() {
        permissions.refresh()
        hotkey.start()
    }

    // MARK: - Hotkey

    private func configureHotkey() {
        hotkey.onPress = { [weak self] in
            // コールバックは main run loop（メインスレッド）上で呼ばれる。
            MainActor.assumeIsolated { self?.handleHotkeyPress() }
        }
        hotkey.onRelease = { [weak self] in
            MainActor.assumeIsolated { self?.handleHotkeyRelease() }
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

    private func handleHotkeyPress() {
        // Phase 3 で録音開始に接続する。現状は状態表示のみ。
        Log.capture.debug("hotkey pressed")
        status.recordingStarted()
    }

    private func handleHotkeyRelease() {
        // Phase 3 で録音停止 → 取り込みに接続する。
        Log.capture.debug("hotkey released")
        status.recordingStopped()
    }
}
