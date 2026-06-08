//
//  MenuBarView.swift
//  vkey
//
//  メニューバーのドロップダウン内容。状態表示と各種操作。
//

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var status: PipelineStatusStore
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        // 状態表示
        Text(status.state.label)

        if let last = status.lastError {
            Text("Last error: \(last)")
        }

        Divider()

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit vkey") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
