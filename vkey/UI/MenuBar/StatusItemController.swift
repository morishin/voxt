//
//  StatusItemController.swift
//  vkey
//
//  メニューバーアイコンを AppKit の NSStatusItem で直接管理する。
//  MenuBarExtra のラベルは ObservableObject の変化を再描画しづらく、
//  symbolEffect も opacity アニメーションも効かないため、RunCat 同様に
//  NSStatusItem.button を Timer で直接更新して滑らかに明滅させる。
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
    private let frameInterval: TimeInterval = 1.0 / 20.0
    private let pulsePeriod: TimeInterval = 1.6   // 明滅 1 周期

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
            setImage("mic")
            stopAnimation()
        case .recording:
            setImage("mic.fill")
            startAnimation()
        case .processing:
            setImage("ellipsis.bubble")
            startAnimation()
        }
    }

    private func setImage(_ symbolName: String) {
        statusItem.button?.image = Self.symbolImage(symbolName)
        statusItem.button?.alphaValue = 1.0
    }

    /// SF Symbol をメニューバー向けに構成したテンプレート画像にする。
    private static func symbolImage(_ name: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Voxt")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    // MARK: - Animation（Timer で alpha を明滅）

    private func startAnimation() {
        guard animationTimer == nil else { return }
        phase = 0
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

    // MARK: - Menu (開く度に動的に再構築)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabledItem(status.state.label))
        if !status.modelAvailable {
            menu.addItem(disabledItem("⚠︎ " + String(localized: "Apple Intelligence is off, so text is inserted without formatting")))
        }
        menu.addItem(.separator())

        // 言語クイック切替
        let languageItem = NSMenuItem(title: String(localized: "Language: \(currentLanguageName)"), action: nil, keyEquivalent: "")
        languageItem.submenu = makeLanguageMenu()
        menu.addItem(languageItem)

        // 直近の結果をコピー
        let copyItem = NSMenuItem(title: String(localized: "Copy Last Result"), action: #selector(copyLastResult), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        menu.addItem(.separator())

        // 歯車アイコンは macOS が「設定」項目に自動付与するもので消せないため、
        // 標準どおり ⌘, ショートカットを付けたままにする。
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
        // 他の言語は設定画面の Language タブで追加ダウンロードする。
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
        // メニューに出るのはダウンロード済みのみなので、そのまま選択する。
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
