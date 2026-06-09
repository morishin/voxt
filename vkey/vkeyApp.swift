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
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appDelegate.coordinator)
                .environmentObject(appDelegate.settings)
                .environmentObject(appDelegate.status)
                .environmentObject(appDelegate.coordinator.permissions)
                .environmentObject(appDelegate.coordinator.languages)
        } label: {
            MenuBarLabel(status: appDelegate.status)
        }

        Settings {
            SettingsView()
                .environmentObject(appDelegate.settings)
                .environmentObject(appDelegate.coordinator.permissions)
                .environmentObject(appDelegate.coordinator.languages)
        }
    }
}

/// メニューバーラベル。状態変化に追従させるため ObservedObject で購読する。
private struct MenuBarLabel: View {
    @ObservedObject var status: PipelineStatusStore

    var body: some View {
        StatusIcon(state: status.state, blinkOn: status.blinkOn)
    }
}
