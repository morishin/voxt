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

    /// 処理中スピナーの回転フレーム。起動時に 1 度だけ事前生成してキャッシュし、
    /// 再生時はキャッシュ画像を差し替えるだけにする（毎フレーム描画しない）。
    private let spinFrameCount = 20  // 20fps で 1 周 1 秒
    private lazy var spinnerFrames: [NSImage] = Self.makeRotationFrames("progress.indicator", count: spinFrameCount)
    private var spinIndex = 0

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
            mode = .none
            setImage("mic")
            stopAnimation()
        case .recording:
            mode = .pulse
            setImage("mic.fill")
            startAnimation()
        case .processing:
            mode = .spin
            spinIndex = 0
            statusItem.button?.alphaValue = 1.0
            statusItem.button?.image = spinnerFrames.first ?? Self.symbolImage("progress.indicator")
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
        switch mode {
        case .pulse:
            phase += frameInterval
            let pulse = (sin(phase * 2 * .pi / pulsePeriod) + 1) / 2
            statusItem.button?.alphaValue = 0.3 + 0.7 * pulse
        case .spin:
            // 事前生成済みフレームを差し替えるだけ（描画コストゼロ）。
            guard !spinnerFrames.isEmpty else { return }
            spinIndex = (spinIndex + 1) % spinnerFrames.count
            statusItem.button?.image = spinnerFrames[spinIndex]
        case .none:
            break
        }
    }

    /// 回転フレームを事前生成する（時計回り、count 枚で 1 周）。
    private static func makeRotationFrames(_ symbolName: String, count: Int) -> [NSImage] {
        guard let base = symbolImage(symbolName) else { return [] }
        return (0..<count).map { i in
            let angle = -2 * CGFloat.pi * CGFloat(i) / CGFloat(count)
            return rotated(base, by: angle)
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
        let installed = languages.installedOptions
        if installed.isEmpty {
            submenu.addItem(disabledItem("ダウンロード済みの言語がありません"))
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
        let other = NSMenuItem(title: "他の言語…", action: #selector(openLanguageSettings), keyEquivalent: "")
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
