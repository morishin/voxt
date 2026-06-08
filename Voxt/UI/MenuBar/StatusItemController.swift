//
//  StatusItemController.swift
//  Voxt
//
//  Manages the menu bar icon directly using AppKit's NSStatusItem.
//  Because MenuBarExtra labels are hard to redraw on ObservableObject changes
//  and neither symbolEffect nor opacity animations work there, we update
//  NSStatusItem.button directly with a Timer to produce a smooth pulse,
//  similar to RunCat.
//

import AppKit
import Combine
import Foundation

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let status: PipelineStatusStore
    private let settings: SettingsStore
    private let languages: LanguageManager
    private let coordinator: AppCoordinator
    private let settingsWindow: SettingsWindowController

    private var cancellables: Set<AnyCancellable> = []
    private var animationTimer: Timer?
    private var phase: Double = 0
    private let frameInterval: TimeInterval = 1.0 / 30.0
    private var pulsePeriod: TimeInterval = 1.4          // Current pulse period (switched per state)
    private let recordingPulsePeriod: TimeInterval = 1.4  // Recording: slow pulse
    private let processingPulsePeriod: TimeInterval = 0.45 // Processing: very fast pulse

    init(status: PipelineStatusStore,
         settings: SettingsStore,
         languages: LanguageManager,
         coordinator: AppCoordinator,
         settingsWindow: SettingsWindowController) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.status = status
        self.settings = settings
        self.languages = languages
        self.coordinator = coordinator
        self.settingsWindow = settingsWindow
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        applyState(status.state)
        observeState()
    }

    // MARK: - State observation

    private func observeState() {
        status.$state
            .removeDuplicates()
            .sink { [weak self] newState in
                self?.applyState(newState)
            }
            .store(in: &cancellables)
    }

    private func applyState(_ state: PipelineStatusStore.UIState) {
        switch state {
        case .ready:
            // Idle: display logo statically.
            setLogoImage()
            stopAnimation()
        case .recording:
            // Recording: slowly pulse the logo.
            setLogoImage()
            startAnimation(period: recordingPulsePeriod)
        case .processing:
            // Processing: pulse the logo very fast to distinguish it from recording.
            setLogoImage()
            startAnimation(period: processingPulsePeriod)
        }
    }

    /// The Voxt brand logo displayed in each state (template image for the menu bar).
    private func setLogoImage() {
        statusItem.button?.image = Self.logoImage()
        statusItem.button?.alphaValue = 1.0
    }

    /// Configures the SVG logo from the asset catalog as a template image sized to the menu bar height.
    private static func logoImage() -> NSImage? {
        guard let base = NSImage(named: "MenuBarIcon"),
              let image = base.copy() as? NSImage else {
            // Fall back to the legacy SF Symbol if the image cannot be loaded.
            return symbolImage("mic")
        }
        let height: CGFloat = 16
        let aspect = base.size.height > 0 ? base.size.width / base.size.height : 1
        image.size = NSSize(width: height * aspect, height: height)
        image.isTemplate = true
        return image
    }

    /// Configures an SF Symbol as a template image suitable for the menu bar.
    private static func symbolImage(_ name: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Voxt")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    // MARK: - Animation (pulse alpha with a Timer)

    private func startAnimation(period: TimeInterval) {
        pulsePeriod = period
        phase = 0   // Reset on period change so the transition is smooth.
        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: frameInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        statusItem.button?.alphaValue = 1.0
    }

    private func tick() {
        phase += frameInterval
        let pulse = (sin(phase * 2 * .pi / pulsePeriod) + 1) / 2
        statusItem.button?.alphaValue = 0.3 + 0.7 * pulse
    }

    // MARK: - Menu (rebuilt dynamically each time it opens)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabledItem(status.state.label))
        if !status.modelAvailable {
            menu.addItem(disabledItem("⚠︎ " + String(localized: "Apple Intelligence is off, so text is inserted without formatting")))
        }
        menu.addItem(.separator())

        // Quick language switcher
        let languageItem = NSMenuItem(title: String(localized: "Language: \(currentLanguageName)"), action: nil, keyEquivalent: "")
        languageItem.submenu = makeLanguageMenu()
        menu.addItem(languageItem)

        // Copy most recent result
        let copyItem = NSMenuItem(title: String(localized: "Copy Last Result"), action: #selector(copyLastResult), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        menu.addItem(.separator())

        // macOS automatically adds a gear icon to the "Settings" item and it cannot be removed,
        // so we keep the standard ⌘, shortcut as-is.
        let settingsItem = NSMenuItem(title: String(localized: "Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: String(localized: "Quit Voxt"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func makeLanguageMenu() -> NSMenu {
        let submenu = NSMenu()
        let installed = languages.installedOptions
        if installed.isEmpty {
            submenu.addItem(disabledItem(String(localized: "No downloaded languages")))
        }
        for option in installed {
            let item = NSMenuItem(title: option.displayName, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.locale.identifier
            if LanguageManager.matches(option, settingIdentifier: settings.defaultLanguageIdentifier) {
                item.state = .on
            }
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        // Other languages can be downloaded from the Language tab in Settings.
        let other = NSMenuItem(title: String(localized: "Other languages…"), action: #selector(openLanguageSettings), keyEquivalent: "")
        other.target = self
        submenu.addItem(other)
        return submenu
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private var currentLanguageName: String {
        LanguageManager.displayName(forIdentifier: settings.defaultLanguageIdentifier)
    }

    // MARK: - Actions

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(copyLastResult) {
            return status.lastResultText != nil
        }
        return true
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else { return }
        // Only downloaded languages appear in the menu, so select directly.
        settings.defaultLanguageIdentifier = identifier
    }

    @objc private func openLanguageSettings() {
        settingsWindow.show(tab: .language)
        Task { await languages.refresh() }
    }

    @objc private func copyLastResult() {
        coordinator.copyLastResult()
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
