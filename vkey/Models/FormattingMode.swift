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

    /// 設定画面で選択中モードの違いを示す説明（before → after の例つき）。
    var explanation: String {
        switch self {
        case .raw:
            return "整形しません。文字起こし結果をそのまま挿入します。"
        case .light:
            return "フィラー除去と句読点の補完など、最小限の整形をします。\n例: 「えーと、明日は10時集合で」→「明日は10時集合で。」"
        case .standard:
            return "自然な書き言葉へ整えます。言い淀みや語順も調整されます。\n例: 「えーと明日って10時集合だっけ」→「明日は10時集合でしたか？」"
        }
    }
}
