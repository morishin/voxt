//
//  InsertionMode.swift
//  Voxt
//
//  テキスト挿入方式。auto は AX 直接挿入を試し、失敗時にクリップボード fallback。
//

import Foundation

enum InsertionMode: String, CaseIterable, Identifiable, Codable, Sendable {
    /// AX 直接挿入を試し、失敗したらクリップボード経由でペースト。
    case auto
    /// AX 直接挿入のみ（失敗時は通知のみ）。
    case direct
    /// 常にクリップボード経由でペースト。
    case paste

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto (直接挿入 → ペースト)"
        case .direct: return "Direct (直接挿入のみ)"
        case .paste: return "Paste (常にペースト)"
        }
    }
}
