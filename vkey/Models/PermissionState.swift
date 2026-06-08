//
//  PermissionState.swift
//  vkey
//
//  各種権限の状態。
//

import Foundation

enum PermissionState: Equatable, Sendable {
    /// まだ確認していない / OS 的に未決定。
    case notDetermined
    /// 許可済み。
    case granted
    /// 拒否済み。システム設定での変更が必要。
    case denied

    var isGranted: Bool { self == .granted }

    var label: String {
        switch self {
        case .notDetermined: return "未確認"
        case .granted: return "許可済み"
        case .denied: return "未許可"
        }
    }

    var symbolName: String {
        switch self {
        case .notDetermined: return "questionmark.circle"
        case .granted: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        }
    }
}

/// アプリが必要とする権限の種類。
enum PermissionKind: String, CaseIterable, Identifiable, Sendable {
    case microphone
    case speechRecognition
    case accessibility
    case inputMonitoring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: return "マイク"
        case .speechRecognition: return "音声認識"
        case .accessibility: return "アクセシビリティ"
        case .inputMonitoring: return "入力監視"
        }
    }

    var purpose: String {
        switch self {
        case .microphone: return "録音に使用します。"
        case .speechRecognition: return "録音音声の文字起こしに使用します。"
        case .accessibility: return "フォーカス中アプリへのテキスト挿入に使用します。"
        case .inputMonitoring: return "Push-to-talk のキー監視に使用します。"
        }
    }

    /// システム設定の該当プライバシーペインを開く URL。
    var settingsURL: URL? {
        let base = "x-apple.systempreferences:com.apple.preference.security?"
        let anchor: String
        switch self {
        case .microphone: anchor = "Privacy_Microphone"
        case .speechRecognition: anchor = "Privacy_SpeechRecognition"
        case .accessibility: anchor = "Privacy_Accessibility"
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        }
        return URL(string: base + anchor)
    }
}
