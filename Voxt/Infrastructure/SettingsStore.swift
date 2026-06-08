//
//  SettingsStore.swift
//  Voxt
//
//  Persistence of user settings. The initial version uses UserDefaults.
//  Each property is automatically saved to UserDefaults when changed.
//

import Foundation
import Combine

@MainActor
final class SettingsStore: ObservableObject {

    private enum Key {
        static let formattingMode = "formattingMode"
        static let customFormattingInstruction = "customFormattingInstruction"
        static let defaultLanguageIdentifier = "defaultLanguageIdentifier"
        static let maxConcurrentModelCalls = "maxConcurrentModelCalls"
        static let maxConcurrentUtterances = "maxConcurrentUtterances"
        static let launchAtLogin = "launchAtLogin"
        static let enableDebugLogging = "enableDebugLogging"
        static let hotKeyKeyCode = "hotKeyKeyCode"
    }

    private let defaults: UserDefaults

    // MARK: - Recording
    /// CGKeyCode of the key used for push-to-talk. Default value is Right Command (0x36).
    @Published var hotKeyKeyCode: Int {
        didSet { defaults.set(hotKeyKeyCode, forKey: Key.hotKeyKeyCode) }
    }

    // MARK: - Language
    /// Default recognition language locale identifier (e.g. "ja-JP").
    @Published var defaultLanguageIdentifier: String {
        didSet { defaults.set(defaultLanguageIdentifier, forKey: Key.defaultLanguageIdentifier) }
    }

    // MARK: - Formatting
    @Published var formattingMode: FormattingMode {
        didSet { defaults.set(formattingMode.rawValue, forKey: Key.formattingMode) }
    }
    /// Maximum character count for custom formatting instructions (to avoid pressuring the token limit).
    static let maxCustomInstructionLength = 200
    /// Additional formatting instructions written by the user. Disabled if empty. Truncated at the maximum length.
    @Published var customFormattingInstruction: String {
        didSet {
            let capped = String(customFormattingInstruction.prefix(Self.maxCustomInstructionLength))
            if capped != customFormattingInstruction {
                customFormattingInstruction = capped
                return
            }
            defaults.set(customFormattingInstruction, forKey: Key.customFormattingInstruction)
        }
    }

    // MARK: - Concurrency (2 parallelism knobs. Tune based on real measurements)
    /// Total number of simultaneous model calls across all utterances. 1 means fully serial.
    @Published var maxConcurrentModelCalls: Int {
        didSet { defaults.set(maxConcurrentModelCalls, forKey: Key.maxConcurrentModelCalls) }
    }
    /// Number of utterances that can be processed simultaneously (for overlapping pipeline stages).
    @Published var maxConcurrentUtterances: Int {
        didSet { defaults.set(maxConcurrentUtterances, forKey: Key.maxConcurrentUtterances) }
    }

    // MARK: - General / Diagnostics
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }
    @Published var enableDebugLogging: Bool {
        didSet { defaults.set(enableDebugLogging, forKey: Key.enableDebugLogging) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Register default values
        defaults.register(defaults: [
            Key.formattingMode: FormattingMode.light.rawValue,
            Key.customFormattingInstruction: "",
            Key.defaultLanguageIdentifier: Locale.current.identifier,
            Key.maxConcurrentModelCalls: 1,
            Key.maxConcurrentUtterances: 2,
            Key.launchAtLogin: false,
            Key.enableDebugLogging: false,
            Key.hotKeyKeyCode: 0x36, // Right Command
        ])

        self.formattingMode = FormattingMode(rawValue: defaults.string(forKey: Key.formattingMode) ?? "") ?? .light
        self.customFormattingInstruction = defaults.string(forKey: Key.customFormattingInstruction) ?? ""
        self.defaultLanguageIdentifier = defaults.string(forKey: Key.defaultLanguageIdentifier) ?? Locale.current.identifier
        self.maxConcurrentModelCalls = defaults.integer(forKey: Key.maxConcurrentModelCalls)
        self.maxConcurrentUtterances = defaults.integer(forKey: Key.maxConcurrentUtterances)
        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        self.enableDebugLogging = defaults.bool(forKey: Key.enableDebugLogging)
        self.hotKeyKeyCode = defaults.integer(forKey: Key.hotKeyKeyCode)
    }
}
