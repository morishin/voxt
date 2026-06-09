//
//  PermissionsView.swift
//  vkey
//
//  権限の状態行。設定画面「一般」タブの権限セクションで使う。
//

import SwiftUI

struct PermissionRow: View {
    @EnvironmentObject private var permissions: PermissionManager
    let kind: PermissionKind
    let state: PermissionState

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: state.symbolName)
                .foregroundStyle(color(for: state))
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title).fontWeight(.medium)
                Text(kind.purpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            actionButton
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch state {
        case .granted:
            Text(state.label).foregroundStyle(.secondary)
        case .notDetermined:
            Button("Allow") { request() }
        case .denied:
            Button("Open System Settings") { permissions.openSettings(for: kind) }
        }
    }

    private func request() {
        switch kind {
        case .microphone:
            Task { await permissions.requestMicrophone() }
        case .speechRecognition:
            Task { await permissions.requestSpeechRecognition() }
        case .accessibility:
            permissions.requestAccessibility()
        case .inputMonitoring:
            permissions.requestInputMonitoring()
        }
    }

    private func color(for state: PermissionState) -> Color {
        switch state {
        case .granted: return .green
        case .notDetermined: return .secondary
        case .denied: return .red
        }
    }
}
