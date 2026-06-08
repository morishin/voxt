//
//  SettingsView.swift
//  Voxt
//
//  Settings screen. Contains two tabs: "General" (aggregates various settings) and "Language" (select and download supported languages).
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
            AboutView()
                .tabItem { Text("About") }
                .tag(SettingsTab.about)
        }
        .frame(width: 460, height: 460)
    }
}

// MARK: - General (aggregates various settings)

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
            // Only show the required permissions prominently at the top when not all permissions are granted.
            if !permissions.allGranted {
                Section {
                    ForEach(missingPermissions) { kind in
                        PermissionRow(kind: kind, state: permissions.state(for: kind))
                    }
                    Button("Re-check") { permissions.refresh() }
                } header: {
                    Label("Voxt needs permission to work", systemImage: "exclamationmark.triangle.fill")
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

            // Show the custom formatting instructions field only when formatting is not set to Off.
            if settings.formattingMode != .raw {
                Section {
                    TextField(
                        "Custom formatting instructions",
                        text: $settings.customFormattingInstruction,
                        prompt: Text("e.g. Capitalize product names like GitHub and macOS"),
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
            return nil // Consume the event so it is not forwarded to other controls.
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
            if event.keyCode == 53 { stopHotkeyRecording(); return } // Esc cancels
            settings.hotKeyKeyCode = Int(event.keyCode)
            stopHotkeyRecording()
        case .flagsChanged:
            // Capture only the moment a modifier key is pressed (ignore key-up).
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

    /// Puts the currently selected (default) language first; the rest are sorted by name.
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
                // Dim languages that are not downloaded since they cannot be selected.
                .foregroundStyle(option.isInstalled ? .primary : .secondary)
            Spacer()
            if option.isInstalled {
                // OS-managed languages (e.g. system languages) cannot be removed by the app, so no button is shown.
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
            // Only downloaded languages can be selected.
            guard option.isInstalled else { return }
            settings.defaultLanguageIdentifier = option.locale.identifier
        }
    }

    private func delete() {
        let wasSelected = isSelected
        Task {
            await languages.remove(option.locale)
            guard wasSelected else { return }
            // When the selected language is deleted, fall back to the always-available system language.
            // If the system language is not available, fall back to the first remaining installed language.
            let systemId = Locale.current.identifier
            if languages.installedOptions.contains(where: { LanguageManager.matches($0, settingIdentifier: systemId) }) {
                settings.defaultLanguageIdentifier = systemId
            } else if let fallback = languages.installedOptions.first {
                settings.defaultLanguageIdentifier = fallback.locale.identifier
            }
        }
    }
}
