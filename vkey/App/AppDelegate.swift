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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // .accessory: Dock に出ず、メニューバーのみで常駐する。
        NSApp.setActivationPolicy(.accessory)
        Log.app.info("vkey launched (accessory mode)")
        coordinator.start()
    }
}
