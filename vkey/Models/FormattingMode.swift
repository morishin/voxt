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
        case .raw: return String(localized: "Off (no formatting)")
        case .light: return String(localized: "Light")
        case .standard: return String(localized: "Standard")
        }
    }

    /// 設定画面で選択中モードの違いを示す説明（before → after の例つき）。
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
