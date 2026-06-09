//
//  SettingsView.swift
//  vkey
//
//  設定画面。タブで General / Recording / Language / Formatting / Insertion / Diagnostics を切り替える。
//

import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var navigation: SettingsNavigation

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
                .tag(SettingsTab.general)
            PermissionsView()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
                .tag(SettingsTab.permissions)
            RecordingSettingsView()
                .tabItem { Label("Recording", systemImage: "mic") }
                .tag(SettingsTab.recording)
            LanguageSettingsView()
                .tabItem { Label("Language", systemImage: "globe") }
                .tag(SettingsTab.language)
            FormattingSettingsView()
                .tabItem { Label("Formatting", systemImage: "text.badge.checkmark") }
                .tag(SettingsTab.formatting)
            InsertionSettingsView()
                .tabItem { Label("Insertion", systemImage: "text.cursor") }
                .tag(SettingsTab.insertion)
            DiagnosticsSettingsView()
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
                .tag(SettingsTab.diagnostics)
        }
        .frame(width: 480, height: 360)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
            Toggle("Show notifications", isOn: $settings.showNotifications)
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Recording

struct RecordingSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var isRecordingHotkey = false
    @State private var eventMonitor: Any?

    var body: some View {
        Form {
            LabeledContent("Push-to-talk key") {
                Button(action: toggleHotkeyRecording) {
                    Text(hotkeyButtonTitle)
                        .frame(minWidth: 150)
                }
            }
            Text("ボタンを押してから、ホットキーにしたいキーを 1 つ押してください（Esc でキャンセル）。押している間だけ録音されるので、Right Command などの修飾キーや F キーが向いています。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
        .onDisappear { stopHotkeyRecording() }
    }

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

// MARK: - Language

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
            Text("録音前に言語を選びます（メニューバーからも切替可能）。未ダウンロードの言語は選択時に取得します。")
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

// MARK: - Formatting

struct FormattingSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Form {
            Picker("Formatting mode", selection: $settings.formattingMode) {
                ForEach(FormattingMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            LabeledContent("Output safety factor") {
                HStack {
                    Slider(value: $settings.outputSafetyFactor, in: 1.0...1.5, step: 0.05)
                    Text(String(format: "%.2f", settings.outputSafetyFactor))
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Insertion

struct InsertionSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Form {
            Picker("Insertion mode", selection: $settings.insertionMode) {
                ForEach(InsertionMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Diagnostics

struct DiagnosticsSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Form {
            Toggle("Enable debug logging", isOn: $settings.enableDebugLogging)
            Section("並列度（実測で調整）") {
                Stepper("Max concurrent model calls: \(settings.maxConcurrentModelCalls)",
                        value: $settings.maxConcurrentModelCalls, in: 1...8)
                Stepper("Max concurrent utterances: \(settings.maxConcurrentUtterances)",
                        value: $settings.maxConcurrentUtterances, in: 1...8)
                Text("並列度の変更はアプリ再起動後に反映されます。on-device モデルは直列化される場合があるため、効果は実測で確認してください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
