//
//  vkeyApp.swift
//  vkey
//
//  Created by morishin on 2026/06/08.
//

import SwiftUI

@main
struct vkeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // メニューバーアイコンとメニューは AppDelegate の StatusItemController(AppKit)が管理する。
        // ここでは設定ウィンドウのみ提供する。
        Settings {
            SettingsView()
                .environmentObject(appDelegate.settings)
                .environmentObject(appDelegate.coordinator.permissions)
                .environmentObject(appDelegate.coordinator.languages)
        }
    }
}
