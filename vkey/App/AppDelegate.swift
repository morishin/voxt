//
//  AppDelegate.swift
//  vkey
//
//  共有オブジェクトの生成と起動処理。Dock アイコンを出さずメニューバー常駐にする。
//

import AppKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    let status = PipelineStatusStore()
    lazy var coordinator = AppCoordinator(settings: settings, status: status)

    private let settingsNavigation = SettingsNavigation()
    private var settingsWindowController: SettingsWindowController?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // .accessory: Dock に出ず、メニューバーのみで常駐する。
        NSApp.setActivationPolicy(.accessory)
        Log.app.info("vkey launched (accessory mode)")
        coordinator.start()

        // 設定画面は自前の NSWindow で管理する（AppKit から SwiftUI Settings を開けないため）。
        let settingsWindow = SettingsWindowController(
            settings: settings,
            permissions: coordinator.permissions,
            languages: coordinator.languages,
            navigation: settingsNavigation
        )
        settingsWindowController = settingsWindow

        // メニューバーアイコンは AppKit の NSStatusItem で管理し、Timer でアニメーションさせる。
        statusItemController = StatusItemController(
            status: status,
            settings: settings,
            languages: coordinator.languages,
            coordinator: coordinator,
            settingsWindow: settingsWindow
        )
    }
}
