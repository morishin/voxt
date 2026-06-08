//
//  SettingsStore.swift
//  vkey
//
//  ユーザー設定の永続化。初期版は UserDefaults を使う。
//  各プロパティは変更時に自動で UserDefaults へ保存する。
//

import Foundation
import Combine

@MainActor
final class SettingsStore: ObservableObject {

    private enum Key {
        static let formattingMode = "formattingMode"
        static let insertionMode = "insertionMode"
        static let maxRecordingSeconds = "maxRecordingSeconds"
        static let defaultLanguageIdentifier = "defaultLanguageIdentifier"
        static let maxConcurrentModelCalls = "maxConcurrentModelCalls"
        static let maxConcurrentUtterances = "maxConcurrentUtterances"
        static let outputSafetyFactor = "outputSafetyFactor"
        static let launchAtLogin = "launchAtLogin"
        static let showNotifications = "showNotifications"
        static let enableDebugLogging = "enableDebugLogging"
        static let hotKeyKeyCode = "hotKeyKeyCode"
    }

    private let defaults: UserDefaults

    // MARK: - Recording
    @Published var maxRecordingSeconds: Double {
        didSet { defaults.set(maxRecordingSeconds, forKey: Key.maxRecordingSeconds) }
    }
    /// Push-to-talk に使うキーの CGKeyCode。初期値は Right Command (0x36)。
    @Published var hotKeyKeyCode: Int {
        didSet { defaults.set(hotKeyKeyCode, forKey: Key.hotKeyKeyCode) }
    }

    // MARK: - Language
    /// 既定の認識言語 locale identifier（例: "ja-JP"）。
    @Published var defaultLanguageIdentifier: String {
        didSet { defaults.set(defaultLanguageIdentifier, forKey: Key.defaultLanguageIdentifier) }
    }

    // MARK: - Formatting
    @Published var formattingMode: FormattingMode {
        didSet { defaults.set(formattingMode.rawValue, forKey: Key.formattingMode) }
    }
    /// 整文で「出力 ≈ 入力」を見込む安全係数。チャンクサイズ計算に使う。
    @Published var outputSafetyFactor: Double {
        didSet { defaults.set(outputSafetyFactor, forKey: Key.outputSafetyFactor) }
    }

    // MARK: - Insertion
    @Published var insertionMode: InsertionMode {
        didSet { defaults.set(insertionMode.rawValue, forKey: Key.insertionMode) }
    }

    // MARK: - Concurrency（並列度 2 ノブ。実測で調整する）
    /// 全発話横断のモデル同時呼び出し総数。1 で完全直列。
    @Published var maxConcurrentModelCalls: Int {
        didSet { defaults.set(maxConcurrentModelCalls, forKey: Key.maxConcurrentModelCalls) }
    }
    /// 同時に処理中にできる発話数（パイプライン段のオーバーラップ用）。
    @Published var maxConcurrentUtterances: Int {
        didSet { defaults.set(maxConcurrentUtterances, forKey: Key.maxConcurrentUtterances) }
    }

    // MARK: - General / Diagnostics
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }
    @Published var showNotifications: Bool {
        didSet { defaults.set(showNotifications, forKey: Key.showNotifications) }
    }
    @Published var enableDebugLogging: Bool {
        didSet { defaults.set(enableDebugLogging, forKey: Key.enableDebugLogging) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // 既定値の登録
        defaults.register(defaults: [
            Key.formattingMode: FormattingMode.light.rawValue,
            Key.insertionMode: InsertionMode.auto.rawValue,
            Key.maxRecordingSeconds: 60.0,
            Key.defaultLanguageIdentifier: Locale.current.identifier,
            Key.maxConcurrentModelCalls: 1,
            Key.maxConcurrentUtterances: 2,
            Key.outputSafetyFactor: 1.15,
            Key.launchAtLogin: false,
            Key.showNotifications: true,
            Key.enableDebugLogging: false,
            Key.hotKeyKeyCode: 0x36, // Right Command
        ])

        self.formattingMode = FormattingMode(rawValue: defaults.string(forKey: Key.formattingMode) ?? "") ?? .light
        self.insertionMode = InsertionMode(rawValue: defaults.string(forKey: Key.insertionMode) ?? "") ?? .auto
        self.maxRecordingSeconds = defaults.double(forKey: Key.maxRecordingSeconds)
        self.defaultLanguageIdentifier = defaults.string(forKey: Key.defaultLanguageIdentifier) ?? Locale.current.identifier
        self.maxConcurrentModelCalls = defaults.integer(forKey: Key.maxConcurrentModelCalls)
        self.maxConcurrentUtterances = defaults.integer(forKey: Key.maxConcurrentUtterances)
        self.outputSafetyFactor = defaults.double(forKey: Key.outputSafetyFactor)
        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        self.showNotifications = defaults.bool(forKey: Key.showNotifications)
        self.enableDebugLogging = defaults.bool(forKey: Key.enableDebugLogging)
        self.hotKeyKeyCode = defaults.integer(forKey: Key.hotKeyKeyCode)
    }
}
