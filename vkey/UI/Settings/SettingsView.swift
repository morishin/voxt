//
//  SettingsView.swift
//  vkey
//
//  設定画面。タブで General / Recording / Language / Formatting / Insertion / Diagnostics を切り替える。
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            PermissionsView()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
            RecordingSettingsView()
                .tabItem { Label("Recording", systemImage: "mic") }
            LanguageSettingsView()
                .tabItem { Label("Language", systemImage: "globe") }
            FormattingSettingsView()
                .tabItem { Label("Formatting", systemImage: "text.badge.checkmark") }
            InsertionSettingsView()
                .tabItem { Label("Insertion", systemImage: "text.cursor") }
            DiagnosticsSettingsView()
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
        }
        .frame(width: 460, height: 320)
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

    /// 競合が少なく PTT に向く修飾キー候補。
    static let selectableHotkeys: [Int] = [0x36, 0x37, 0x3D, 0x3A, 0x3F] // R-Cmd, L-Cmd, R-Opt, L-Opt, Fn

    var body: some View {
        Form {
            LabeledContent("Max recording duration") {
                HStack {
                    Slider(value: $settings.maxRecordingSeconds, in: 10...300, step: 5)
                    Text("\(Int(settings.maxRecordingSeconds)) s")
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
            }
            // 主要な修飾キーから選択する。任意キーへの対応は将来拡張。
            Picker("Push-to-talk key", selection: $settings.hotKeyKeyCode) {
                ForEach(Self.selectableHotkeys, id: \.self) { code in
                    Text(HotkeyMonitor.displayName(for: CGKeyCode(code))).tag(code)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
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

    var body: some View {
        HStack {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            Text(option.displayName)
            Spacer()
            if option.isInstalled {
                Label("DL済み", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
            } else {
                Button("ダウンロード") {
                    Task { await languages.prepare(option.locale) }
                }
                .buttonStyle(.borderless)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
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
            Stepper("Max concurrent model calls: \(settings.maxConcurrentModelCalls)",
                    value: $settings.maxConcurrentModelCalls, in: 1...8)
            Stepper("Max concurrent utterances: \(settings.maxConcurrentUtterances)",
                    value: $settings.maxConcurrentUtterances, in: 1...8)
        }
        .formStyle(.grouped)
        .padding()
    }
}
