//
//  MenuBarView.swift
//  vkey
//
//  メニューバーのドロップダウン内容。状態表示・言語クイック切替・各種操作。
//

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var status: PipelineStatusStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var languages: LanguageManager

    var body: some View {
        // 状態表示
        Text(status.state.label)

        if let last = status.lastError {
            Text("Last error: \(last)")
        }

        Divider()

        // 言語クイック切替
        Menu("Language: \(currentLanguageName)") {
            if languages.options.isEmpty {
                Text("読み込み中…")
            }
            ForEach(languages.options) { option in
                Button {
                    select(option)
                } label: {
                    Text(menuLabel(for: option))
                }
            }
            Divider()
            Button("言語リストを更新") {
                Task { await languages.refresh() }
            }
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

    private var currentLanguageName: String {
        LanguageManager.displayName(forIdentifier: settings.defaultLanguageIdentifier)
    }

    private func menuLabel(for option: LanguageManager.LanguageOption) -> String {
        var label = option.displayName
        if LanguageManager.matches(option, settingIdentifier: settings.defaultLanguageIdentifier) {
            label = "✓ " + label
        }
        if !option.isInstalled {
            label += "（未ダウンロード）"
        }
        return label
    }

    private func select(_ option: LanguageManager.LanguageOption) {
        settings.defaultLanguageIdentifier = option.locale.identifier
        if !option.isInstalled {
            Task { await languages.prepare(option.locale) }
        }
    }
}
