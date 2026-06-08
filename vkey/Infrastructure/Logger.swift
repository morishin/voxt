//
//  Logger.swift
//  vkey
//
//  開発者向けの OSLog ロガー。発話本文・変換本文などの個人情報は原則残さない。
//

import OSLog

/// アプリ共通の Logger 名前空間。カテゴリごとに分けて取得する。
enum Log {
    /// サブシステム名。Bundle Identifier を使う。
    static let subsystem = Bundle.main.bundleIdentifier ?? "me.morishin.vkey"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let pipeline = Logger(subsystem: subsystem, category: "pipeline")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let speech = Logger(subsystem: subsystem, category: "speech")
    static let formatting = Logger(subsystem: subsystem, category: "formatting")
    static let insertion = Logger(subsystem: subsystem, category: "insertion")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let settings = Logger(subsystem: subsystem, category: "settings")
}
