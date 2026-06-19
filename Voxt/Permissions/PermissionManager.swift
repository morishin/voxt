//
//  PermissionManager.swift
//  Voxt
//
//  Microphone / Speech Recognition / Accessibility / Input Monitoring の
//  権限状態を確認・要求・システム設定誘導する。
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

    /// 全権限の現在状態を再取得する。
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

    /// アクセシビリティ権限を要求する（システムダイアログを表示）。
    /// 実際のテキスト挿入で使う CGEvent 投函（Cmd-V 合成）に必要な「イベント投函」権限を要求する。
    /// AXIsProcessTrustedWithOptions の汎用「コンピュータを制御」プロンプトはアクセサリアプリ
    /// （Dock なし常駐）だと表示されないことがあるため、CGRequestPostEventAccess を使ってダイアログを確実に出す。
    /// アクセシビリティの TCC バケットは共通なので、ここで許可すれば AX 直接挿入も使えるようになる。
    func requestAccessibility() {
        let granted = CGRequestPostEventAccess()
        accessibility = granted ? .granted : .denied
    }

    func requestInputMonitoring() {
        let result = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        inputMonitoring = result ? .granted : (inputMonitoring == .granted ? .granted : .denied)
    }

    /// 該当する権限のシステム設定ペインを開く。
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
