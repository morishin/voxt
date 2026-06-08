//
//  PermissionState.swift
//  Voxt
//
//  State of various permissions.
//

import Foundation

enum PermissionState: Equatable, Sendable {
    /// Not yet checked / undetermined at the OS level.
    case notDetermined
    /// Permission granted.
    case granted
    /// Permission denied. A change in System Settings is required.
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

/// The types of permissions required by the app.
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

    /// URL that opens the relevant privacy pane in System Settings.
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
