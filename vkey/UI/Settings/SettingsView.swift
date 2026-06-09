//
//  SettingsView.swift
//  vkey
//
//  設定画面。タブは「一般」（各種設定を集約）と「言語」（対応言語の選択・DL）の 2 つ。
//

import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var navigation: SettingsNavigation

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            GeneralSettingsView()
                .tabItem { Label("一般", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            LanguageSettingsView()
                .tabItem { Label("言語", systemImage: "globe") }
                .tag(SettingsTab.language)
        }
        .frame(width: 460, height: 460)
    }
}

// MARK: - 一般（各種設定を集約）

struct GeneralSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var permissions: PermissionManager

    @State private var isRecordingHotkey = false
    @State private var eventMonitor: Any?

    var body: some View {
        Form {
            Section("一般") {
                Toggle("ログイン時に起動", isOn: $settings.launchAtLogin)
                Toggle("通知を表示", isOn: $settings.showNotifications)
            }

            Section("ホットキー") {
                LabeledContent("Push-to-talk キー") {
                    Button(action: toggleHotkeyRecording) {
                        Text(hotkeyButtonTitle).frame(minWidth: 150)
                    }
                }
                Text("ボタンを押してから、ホットキーにしたいキーを 1 つ押してください（Esc でキャンセル）。押している間だけ録音されるので、Right Command などの修飾キーや F キーが向いています。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("整形") {
                Picker("整形モード", selection: $settings.formattingMode) {
                    ForEach(FormattingMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            Section("挿入") {
                Picker("挿入方式", selection: $settings.insertionMode) {
                    ForEach(InsertionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            Section {
                ForEach(PermissionKind.allCases) { kind in
                    PermissionRow(kind: kind, state: permissions.state(for: kind))
                }
                Button("再チェック") { permissions.refresh() }
            } header: {
                Text("権限")
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { permissions.refresh() }
        .onDisappear { stopHotkeyRecording() }
    }

    // MARK: Hotkey recorder

    private var hotkeyButtonTitle: String {
        isRecordingHotkey
            ? "キーを押してください…"
            : HotkeyMonitor.displayName(for: CGKeyCode(settings.hotKeyKeyCode))
    }

    private func toggleHotkeyRecording() {
        isRecordingHotkey ? stopHotkeyRecording() : startHotkeyRecording()
    }

    private func startHotkeyRecording() {
        isRecordingHotkey = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handleHotkeyEvent(event)
            return nil // イベントを消費し、他のコントロールへ渡さない。
        }
    }

    private func stopHotkeyRecording() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        isRecordingHotkey = false
    }

    private func handleHotkeyEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            if event.keyCode == 53 { stopHotkeyRecording(); return } // Esc でキャンセル
            settings.hotKeyKeyCode = Int(event.keyCode)
            stopHotkeyRecording()
        case .flagsChanged:
            // 修飾キーが「押された」瞬間のみ捕捉する（離した瞬間は無視）。
            let code = CGKeyCode(event.keyCode)
            guard let flag = Self.modifierFlag(for: code), event.modifierFlags.contains(flag) else { return }
            settings.hotKeyKeyCode = Int(code)
            stopHotkeyRecording()
        default:
            break
        }
    }

    private static func modifierFlag(for keyCode: CGKeyCode) -> NSEvent.ModifierFlags? {
        switch keyCode {
        case 0x36, 0x37: return .command
        case 0x38, 0x3C: return .shift
        case 0x3A, 0x3D: return .option
        case 0x3B, 0x3E: return .control
        case 0x3F: return .function
        default: return nil
        }
    }
}

// MARK: - 言語

struct LanguageSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var languages: LanguageManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("対応言語")
                    .font(.headline)
                Spacer()
                if languages.isLoading {
                    ProgressView().controlSize(.small)
                }
                Button("更新") { Task { await languages.refresh() } }
            }
            Text("録音前に言語を選びます（メニューバーからも切替可能）。未ダウンロードの言語はダウンロード後に選べます。")
                .font(.caption)
                .foregroundStyle(.secondary)

            List(languages.options) { option in
                LanguageRow(option: option)
            }
            .frame(maxHeight: .infinity)
        }
        .padding()
        .task { if languages.options.isEmpty { await languages.refresh() } }
    }
}

private struct LanguageRow: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var languages: LanguageManager
    let option: LanguageManager.LanguageOption

    private var isSelected: Bool {
        LanguageManager.matches(option, settingIdentifier: settings.defaultLanguageIdentifier)
    }

    private var isDownloading: Bool { languages.isDownloading(option) }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            Text(option.displayName)
                // 未ダウンロードは選択不可なので淡色表示。
                .foregroundStyle(option.isInstalled ? .primary : .secondary)
            Spacer()
            if option.isInstalled {
                Label("DL済み", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
            } else if isDownloading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("ダウンロード中…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("ダウンロード") {
                    Task { await languages.prepare(option.locale) }
                }
                .buttonStyle(.borderless)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // ダウンロード済みのみ選択可能。
            guard option.isInstalled else { return }
            settings.defaultLanguageIdentifier = option.locale.identifier
        }
    }
}
