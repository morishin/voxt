//
//  FormattingMode.swift
//  vkey
//
//  整形強度モード。raw は整形 OFF（障害切り分け用）。
//

import Foundation

enum FormattingMode: String, CaseIterable, Identifiable, Codable, Sendable {
    /// 整形なし。文字起こし結果をそのまま使う。
    case raw
    /// フィラー除去 + 句読点補完を中心とした軽い整形。
    case light
    /// 自然な書き言葉へ整える標準整形。
    case standard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .raw: return "Off (整形なし)"
        case .light: return "Light (軽い整形)"
        case .standard: return "Standard (標準整形)"
        }
    }
}
