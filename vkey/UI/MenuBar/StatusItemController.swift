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

    private enum AnimationMode {
        case none
        case pulse  // 録音中: 明滅
        case spin   // 処理中: 回転スピナー
    }

    private var cancellables: Set<AnyCancellable> = []
    private var animationTimer: Timer?
    private var phase: Double = 0
    private var mode: AnimationMode = .none
    private let frameInterval: TimeInterval = 1.0 / 20.0
    private let pulsePeriod: TimeInterval = 1.6   // 明滅 1 周期
    private let spinPeriod: TimeInterval = 1.0    // 回転 1 周期

    /// 処理中スピナーの元画像（回転して使う）。
    private lazy var spinnerBaseImage: NSImage? = Self.symbolImage("arrow.triangle.2.circlepath")

    init(status: PipelineStatusStore,
         settings: SettingsStore,
         languages: LanguageManager,
         coordinator: AppCoordinator) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.status = status
        self.settings = settings
        self.languages = languages
        self.coordinator = coordinator
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
            mode = .none
            setImage("mic")
            stopAnimation()
        case .recording:
            mode = .pulse
            setImage("mic.fill")
            startAnimation()
        case .processing:
            mode = .spin
            // 画像は tick で回転して差し替える。初期フレームを置いておく。
            statusItem.button?.image = spinnerBaseImage
            statusItem.button?.alphaValue = 1.0
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
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "vkey")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    // MARK: - Animation（Timer で明滅 or 回転）

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
        switch mode {
        case .pulse:
            let pulse = (sin(phase * 2 * .pi / pulsePeriod) + 1) / 2
            statusItem.button?.alphaValue = 0.3 + 0.7 * pulse
        case .spin:
            // 時計回りに回転。
            let angle = -2 * .pi * (phase.truncatingRemainder(dividingBy: spinPeriod) / spinPeriod)
            if let base = spinnerBaseImage {
                statusItem.button?.image = Self.rotated(base, by: CGFloat(angle))
            }
        case .none:
            break
        }
    }

    /// NSImage を中心まわりに回転した新しいテンプレート画像を返す。
    private static func rotated(_ base: NSImage, by radians: CGFloat) -> NSImage {
        let size = base.size
        let image = NSImage(size: size)
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.rotate(by: radians)
            ctx.translateBy(x: -size.width / 2, y: -size.height / 2)
        }
        base.draw(in: NSRect(origin: .zero, size: size))
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    // MARK: - Menu (開く度に動的に再構築)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabledItem(status.state.label))
        if !status.modelAvailable {
            menu.addItem(disabledItem("⚠︎ Apple Intelligence が無効のため整形なしで挿入します"))
        }
        menu.addItem(.separator())

        // 言語クイック切替
        let languageItem = NSMenuItem(title: "Language: \(currentLanguageName)", action: nil, keyEquivalent: "")
        languageItem.submenu = makeLanguageMenu()
        menu.addItem(languageItem)

        // Last Result をコピー
        let copyItem = NSMenuItem(title: "Last Result をコピー", action: #selector(copyLastResult), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit vkey", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func makeLanguageMenu() -> NSMenu {
        let submenu = NSMenu()
        if languages.options.isEmpty {
            submenu.addItem(disabledItem("読み込み中…"))
        }
        for option in languages.options {
            let item = NSMenuItem(title: languageLabel(for: option), action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.locale.identifier
            if LanguageManager.matches(option, settingIdentifier: settings.defaultLanguageIdentifier) {
                item.state = .on
            }
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let refresh = NSMenuItem(title: "言語リストを更新", action: #selector(refreshLanguages), keyEquivalent: "")
        refresh.target = self
        submenu.addItem(refresh)
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

    private func languageLabel(for option: LanguageManager.LanguageOption) -> String {
        option.isInstalled ? option.displayName : option.displayName + "（未ダウンロード）"
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
        settings.defaultLanguageIdentifier = identifier
        if let option = languages.options.first(where: { $0.locale.identifier == identifier }), !option.isInstalled {
            Task { await languages.prepare(option.locale) }
        }
    }

    @objc private func refreshLanguages() {
        Task { await languages.refresh() }
    }

    @objc private func copyLastResult() {
        coordinator.copyLastResult()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
