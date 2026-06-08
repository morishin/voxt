//
//  Logger.swift
//  Voxt
//
//  OSLog logger for developers. Personal information such as utterance content and converted text is not logged as a rule.
//

import OSLog

/// Common Logger namespace for the app. Obtained separately per category.
/// Because the project's default actor isolation is MainActor,
/// each property is marked nonisolated so it can be used from non-main actors (Logger is Sendable).
enum Log {
    /// Subsystem name. Uses the Bundle Identifier.
    nonisolated static let subsystem = Bundle.main.bundleIdentifier ?? "me.morishin.voxt"

    nonisolated static let app = Logger(subsystem: subsystem, category: "app")
    nonisolated static let pipeline = Logger(subsystem: subsystem, category: "pipeline")
    nonisolated static let capture = Logger(subsystem: subsystem, category: "capture")
    nonisolated static let speech = Logger(subsystem: subsystem, category: "speech")
    nonisolated static let formatting = Logger(subsystem: subsystem, category: "formatting")
    nonisolated static let insertion = Logger(subsystem: subsystem, category: "insertion")
    nonisolated static let permissions = Logger(subsystem: subsystem, category: "permissions")
    nonisolated static let settings = Logger(subsystem: subsystem, category: "settings")
}
