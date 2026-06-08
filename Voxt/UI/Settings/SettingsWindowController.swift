//
//  SettingsWindowController.swift
//  Voxt
//
//  Manages the Settings window with a custom NSWindow.
//  On macOS, AppKit cannot open a SwiftUI Settings scene directly (showSettingsWindow: is
//  blocked with "Please use SettingsLink"), so we host SettingsView in an NSHostingController
//  inside a custom window instead.
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {

    private let settings: SettingsStore
    private let permissions: PermissionManager
    private let languages: LanguageManager
    private let navigation: SettingsNavigation
    private var window: NSWindow?

    init(settings: SettingsStore,
         permissions: PermissionManager,
         languages: LanguageManager,
         navigation: SettingsNavigation) {
        self.settings = settings
        self.permissions = permissions
        self.languages = languages
        self.navigation = navigation
    }

    /// Brings the Settings window to the front. If a tab is specified, that tab is selected.
    func show(tab: SettingsTab? = nil) {
        if let tab { navigation.selectedTab = tab }

        if window == nil {
            let root = SettingsView()
                .environmentObject(settings)
                .environmentObject(permissions)
                .environmentObject(languages)
                .environmentObject(navigation)
            let hosting = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "Voxt Settings")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            // Ensure the window appears on the current Space even if opened from another Space.
            window.collectionBehavior = [.moveToActiveSpace]
            window.center()
            self.window = window
        }

        // For accessory apps, activate alone can leave the window behind other apps,
        // so we use orderFrontRegardless to guarantee it comes to the very front.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
