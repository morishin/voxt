//
//  PermissionManager.swift
//  Voxt
//
//  Checks, requests, and guides users to system settings for
//  Microphone / Speech Recognition / Accessibility / Input Monitoring permissions.
//

import Foundation
import Combine
import AVFoundation
import Speech
import ApplicationServices
import CoreGraphics
import IOKit.hid
import AppKit
import OSLog

@MainActor
final class PermissionManager: ObservableObject {

    @Published private(set) var microphone: PermissionState = .notDetermined
    @Published private(set) var speechRecognition: PermissionState = .notDetermined
    @Published private(set) var accessibility: PermissionState = .notDetermined
    @Published private(set) var inputMonitoring: PermissionState = .notDetermined

    var allGranted: Bool {
        microphone.isGranted && speechRecognition.isGranted
            && accessibility.isGranted && inputMonitoring.isGranted
    }

    func state(for kind: PermissionKind) -> PermissionState {
        switch kind {
        case .microphone: return microphone
        case .speechRecognition: return speechRecognition
        case .accessibility: return accessibility
        case .inputMonitoring: return inputMonitoring
        }
    }

    // MARK: - Refresh

    /// Re-fetches the current state of all permissions.
    func refresh() {
        microphone = Self.mapAVAuthorization(AVCaptureDevice.authorizationStatus(for: .audio))
        speechRecognition = Self.mapSpeechAuthorization(SFSpeechRecognizer.authorizationStatus())
        accessibility = AXIsProcessTrusted() ? .granted : .denied
        inputMonitoring = Self.mapHIDAccess(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent))
        Log.permissions.info("permissions refreshed: mic=\(self.microphone.label, privacy: .public) speech=\(self.speechRecognition.label, privacy: .public) ax=\(self.accessibility.label, privacy: .public) input=\(self.inputMonitoring.label, privacy: .public)")
    }

    // MARK: - Requests

    func requestMicrophone() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphone = granted ? .granted : .denied
    }

    func requestSpeechRecognition() async {
        let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        speechRecognition = Self.mapSpeechAuthorization(status)
    }

    /// Requests accessibility permission (shows a system dialog).
    /// Requests the "post events" permission needed for CGEvent posting (Cmd-V synthesis) used in actual text insertion.
    /// The generic "control your computer" prompt from AXIsProcessTrustedWithOptions may not appear for accessory apps
    /// (resident without a Dock icon), so CGRequestPostEventAccess is used to reliably show the dialog.
    /// Since the TCC bucket for accessibility is shared, granting this also enables direct AX insertion.
    func requestAccessibility() {
        let granted = CGRequestPostEventAccess()
        accessibility = granted ? .granted : .denied
    }

    func requestInputMonitoring() {
        let result = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        inputMonitoring = result ? .granted : (inputMonitoring == .granted ? .granted : .denied)
    }

    /// Opens the System Settings pane for the relevant permission.
    func openSettings(for kind: PermissionKind) {
        guard let url = kind.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Mapping helpers

    private static func mapAVAuthorization(_ status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    private static func mapSpeechAuthorization(_ status: SFSpeechRecognizerAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    private static func mapHIDAccess(_ access: IOHIDAccessType) -> PermissionState {
        switch access {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied: return .denied
        default: return .notDetermined
        }
    }
}
