//
//  InsertionMode.swift
//  Voxt
//
//  Text insertion method. auto attempts AX direct insertion and falls back to clipboard on failure.
//

import Foundation

enum InsertionMode: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Attempts AX direct insertion; pastes via clipboard if it fails.
    case auto
    /// AX direct insertion only (notification only on failure).
    case direct
    /// Always pastes via clipboard.
    case paste

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto (direct → paste fallback)"
        case .direct: return "Direct (direct insertion only)"
        case .paste: return "Paste (always paste)"
        }
    }
}
