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
            // ホットキーの本格的な設定 UI は Phase 2 で追加する。
            LabeledContent("Push-to-talk key code") {
                Text("0x\(String(settings.hotKeyKeyCode, radix: 16)) (設定 UI は Phase 2 で追加)")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Language

struct LanguageSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Form {
            // 動的な対応言語リストは Phase 7 で追加する。現状は識別子の直接編集。
            LabeledContent("Default language") {
                TextField("locale identifier", text: $settings.defaultLanguageIdentifier)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
            Text("言語のクイック切替・資産ダウンロードは Phase 7 で追加します。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
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
