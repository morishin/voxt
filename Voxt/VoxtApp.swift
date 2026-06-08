//
//  VoxtApp.swift
//  Voxt
//
//  Created by morishin on 2026/06/08.
//

import SwiftUI

@main
struct VoxtApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar, icon, and settings window are all managed by AppDelegate's
        // StatusItemController / SettingsWindowController (AppKit).
        // SwiftUI App requires at least one Scene, so an empty Settings scene is placed here.
        Settings {
            EmptyView()
        }
    }
}
