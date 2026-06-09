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
                .tabItem { Text("General") }
                .tag(SettingsTab.general)
            LanguageSettingsView()
                .tabItem { Text("Language") }
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

    private var missingPermissions: [PermissionKind] {
        PermissionKind.allCases.filter { permissions.state(for: $0) != .granted }
    }

    var body: some View {
        Form {
            // 権限が揃っていない時だけ、一番上に目立つ形で要許可の権限を表示する。
            if !permissions.allGranted {
                Section {
                    ForEach(missingPermissions) { kind in
                        PermissionRow(kind: kind, state: permissions.state(for: kind))
                    }
                    Button("Re-check") { permissions.refresh() }
                } header: {
                    Label("vkey needs permission to work", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.headline)
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }

            Section("Hotkey") {
                LabeledContent("Push-to-talk key") {
                    Button(action: toggleHotkeyRecording) {
                        Text(hotkeyButtonTitle).frame(minWidth: 150)
                    }
                }
                Text("Press the button, then press the single key you want as the hotkey (Esc to cancel). Recording happens only while the key is held, so modifier keys such as Right Command or the function keys work well.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Formatting") {
                Picker("Formatting mode", selection: $settings.formattingMode) {
                    ForEach(FormattingMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Text(settings.formattingMode.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Off 以外のときだけ、追加のカスタム整形指示を書けるようにする。
            if settings.formattingMode != .raw {
                Section {
                    TextField(
                        "Custom formatting instructions",
                        text: $settings.customFormattingInstruction,
                        prompt: Text("e.g. Use a formal tone / Prefix bullet points with a dash"),
                        axis: .vertical
                    )
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .lineLimit(3, reservesSpace: true)

                    HStack {
                        Text("Add extra rules to apply when formatting (no translation or summarizing).")
                        Spacer()
                        Text(verbatim: "\(settings.customFormattingInstruction.count)/\(SettingsStore.maxCustomInstructionLength)")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } header: {
                    Text("Custom formatting instructions (optional)")
                }
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
            ? String(localized: "Press a key…")
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
                Text("Supported languages")
                    .font(.headline)
                Spacer()
                if languages.isLoading {
                    ProgressView().controlSize(.small)
                }
                Button("Refresh") { Task { await languages.refresh() } }
            }
            Text("Choose the language before recording (also switchable from the menu bar). Languages that aren't downloaded become selectable after downloading.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List(sortedOptions) { option in
                LanguageRow(option: option)
            }
            .frame(maxHeight: .infinity)
        }
        .padding()
        .task { if languages.options.isEmpty { await languages.refresh() } }
    }

    /// 選択中（デフォルト）の言語を先頭に、残りは名前順に並べる。
    private var sortedOptions: [LanguageManager.LanguageOption] {
        languages.options.sorted { a, b in
            let aSel = LanguageManager.matches(a, settingIdentifier: settings.defaultLanguageIdentifier)
            let bSel = LanguageManager.matches(b, settingIdentifier: settings.defaultLanguageIdentifier)
            if aSel != bSel { return aSel }
            return a.displayName.localizedCompare(b.displayName) == .orderedAscending
        }
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
                // OS 管理（システム言語など）はアプリから削除できないのでボタンを出さない。
                if option.isRemovable {
                    Button("Delete") { delete() }
                        .buttonStyle(.borderless)
                }
            } else if isDownloading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Downloading…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Download") {
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

    private func delete() {
        let wasSelected = isSelected
        Task {
            await languages.remove(option.locale)
            guard wasSelected else { return }
            // 選択中の言語を削除したら、常に利用可能なシステム言語へ戻す。
            // システム言語が無ければ残りのインストール済み言語の先頭へ。
            let systemId = Locale.current.identifier
            if languages.installedOptions.contains(where: { LanguageManager.matches($0, settingIdentifier: systemId) }) {
                settings.defaultLanguageIdentifier = systemId
            } else if let fallback = languages.installedOptions.first {
                settings.defaultLanguageIdentifier = fallback.locale.identifier
            }
        }
    }
}
