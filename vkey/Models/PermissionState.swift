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
        case .notDetermined: return String(localized: "Not determined")
        case .granted: return String(localized: "Granted")
        case .denied: return String(localized: "Not granted")
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
        case .microphone: return String(localized: "Microphone")
        case .speechRecognition: return String(localized: "Speech Recognition")
        case .accessibility: return String(localized: "Accessibility")
        case .inputMonitoring: return String(localized: "Input Monitoring")
        }
    }

    var purpose: String {
        switch self {
        case .microphone: return String(localized: "Used for recording.")
        case .speechRecognition: return String(localized: "Used to transcribe recorded audio.")
        case .accessibility: return String(localized: "Used to insert text into the focused app.")
        case .inputMonitoring: return String(localized: "Used to monitor the push-to-talk key.")
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
