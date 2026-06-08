//
//  FormattingMode.swift
//  Voxt
//
//  Formatting intensity mode. raw means formatting OFF (for troubleshooting).
//

import Foundation

enum FormattingMode: String, CaseIterable, Identifiable, Codable, Sendable {
    /// No formatting. Uses the transcription result as-is.
    case raw
    /// Light formatting focused on filler removal and punctuation completion.
    case light
    /// Standard formatting that shapes text into natural written language.
    case standard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .raw: return String(localized: "Off (no formatting)")
        case .light: return String(localized: "Light")
        case .standard: return String(localized: "Standard")
        }
    }

    /// Description shown in the settings screen to illustrate the selected mode (with before → after examples).
    var explanation: String {
        switch self {
        case .raw:
            return String(localized: "No formatting. The transcription is inserted as-is.")
        case .light:
            return String(localized: "Minimal formatting such as removing fillers and adding punctuation.\nExample: \"um, so we meet at 10 tomorrow\" → \"We meet at 10 tomorrow.\"")
        case .standard:
            return String(localized: "Edits into natural written language; wording and order are adjusted too.\nExample: \"um is it 10 tomorrow we're meeting\" → \"Are we meeting at 10 tomorrow?\"")
        }
    }
}
