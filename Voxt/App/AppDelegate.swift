//
//  AppDelegate.swift
//  Voxt
//
//  Creates shared objects and handles launch. Runs as a menu bar app without a Dock icon.
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
        // .accessory: Runs in the menu bar only, without appearing in the Dock.
        NSApp.setActivationPolicy(.accessory)
        Log.app.info("Voxt launched (accessory mode)")
        coordinator.start()

        // The settings screen is managed with a custom NSWindow (because AppKit cannot open SwiftUI Settings directly).
        let settingsWindow = SettingsWindowController(
            settings: settings,
            permissions: coordinator.permissions,
            languages: coordinator.languages,
            navigation: settingsNavigation
        )
        settingsWindowController = settingsWindow

        // The menu bar icon is managed via AppKit's NSStatusItem and animated using a Timer.
        statusItemController = StatusItemController(
            status: status,
            settings: settings,
            languages: coordinator.languages,
            coordinator: coordinator,
            settingsWindow: settingsWindow
        )
    }
}
