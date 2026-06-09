//
//  Logger.swift
//  vkey
//
//  開発者向けの OSLog ロガー。発話本文・変換本文などの個人情報は原則残さない。
//

import OSLog

/// アプリ共通の Logger 名前空間。カテゴリごとに分けて取得する。
/// プロジェクトのデフォルトアクター分離が MainActor のため、
/// 非メイン actor からも使えるよう各プロパティを nonisolated にする（Logger は Sendable）。
enum Log {
    /// サブシステム名。Bundle Identifier を使う。
    nonisolated static let subsystem = Bundle.main.bundleIdentifier ?? "me.morishin.vkey"

    nonisolated static let app = Logger(subsystem: subsystem, category: "app")
    nonisolated static let pipeline = Logger(subsystem: subsystem, category: "pipeline")
    nonisolated static let capture = Logger(subsystem: subsystem, category: "capture")
    nonisolated static let speech = Logger(subsystem: subsystem, category: "speech")
    nonisolated static let formatting = Logger(subsystem: subsystem, category: "formatting")
    nonisolated static let insertion = Logger(subsystem: subsystem, category: "insertion")
    nonisolated static let permissions = Logger(subsystem: subsystem, category: "permissions")
    nonisolated static let settings = Logger(subsystem: subsystem, category: "settings")
}
