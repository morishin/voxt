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
    @StateObject private var settings = SettingsStore()
    @StateObject private var status = PipelineStatusStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(settings)
                .environmentObject(status)
        } label: {
            StatusIcon(state: status.state)
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
        }
    }
}
