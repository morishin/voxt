//
//  PermissionsView.swift
//  vkey
//
//  権限の状態一覧と、要求・システム設定誘導・再チェックの UI。
//

import SwiftUI

struct PermissionsView: View {
    @EnvironmentObject private var permissions: PermissionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(PermissionKind.allCases) { kind in
                PermissionRow(kind: kind, state: permissions.state(for: kind))
            }
            Spacer()
            HStack {
                Spacer()
                Button("再チェック") { permissions.refresh() }
            }
        }
        .padding()
        .onAppear { permissions.refresh() }
    }
}

private struct PermissionRow: View {
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
            Button("許可") { request() }
        case .denied:
            Button("システム設定を開く") { permissions.openSettings(for: kind) }
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
