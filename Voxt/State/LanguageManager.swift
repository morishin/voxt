//
//  LanguageManager.swift
//  Voxt
//
//  Dynamically computes supported languages (= transcribable by Speech ∩ supported by Foundation Models)
//  and provides the installation status of on-device assets. Used for quick language switching.
//

import Foundation
import Combine
import Speech
import FoundationModels
import OSLog

@MainActor
final class LanguageManager: ObservableObject {

    struct LanguageOption: Identifiable, Sendable {
        let locale: Locale
        let isInstalled: Bool
        /// Whether the remove button should be shown. False for the system language (managed by the OS and cannot be removed).
        let isRemovable: Bool

        var id: String { locale.identifier }

        /// Localized language name.
        var displayName: String {
            Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
        }
    }

    @Published private(set) var options: [LanguageOption] = []
    @Published private(set) var isLoading = false
    /// Set of locale identifiers currently being downloaded.
    @Published private(set) var downloadingIdentifiers: Set<String> = []
    /// BCP47 IDs of languages that have been "removed" (reservation released). Since they may remain
    /// in installedLocales for a while after release, this is used to immediately treat them as uninstalled in the UI.
    private var removedIdentifiers: Set<String> = []

    /// Only installed languages.
    var installedOptions: [LanguageOption] { options.filter(\.isInstalled) }

    func isDownloading(_ option: LanguageOption) -> Bool {
        downloadingIdentifiers.contains(option.locale.identifier)
    }

    /// Re-fetches the list of supported languages and their installation status.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let supported = await SpeechTranscriber.supportedLocales
        let installedIds = Set((await SpeechTranscriber.installedLocales).map { $0.identifier(.bcp47) })
        // The system language is managed by the OS and cannot be removed, so no remove button is shown.
        let systemLanguageCode = Locale.current.language.languageCode?.identifier
        let model = SystemLanguageModel.default

        let opts: [LanguageOption] = supported
            .filter { model.supportsLocale($0) }
            .map { locale in
                let bcp47 = locale.identifier(.bcp47)
                let installed = installedIds.contains(bcp47) && !removedIdentifiers.contains(bcp47)
                let isSystemLanguage = locale.language.languageCode?.identifier == systemLanguageCode
                let removable = installed && !isSystemLanguage
                return LanguageOption(locale: locale, isInstalled: installed, isRemovable: removable)
            }
            .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }

        options = opts
        Log.speech.info("available languages: \(opts.count, privacy: .public)")
    }

    /// Downloads and installs assets for the specified locale, then updates the state.
    func prepare(_ locale: Locale) async {
        let id = locale.identifier
        downloadingIdentifiers.insert(id)
        defer { downloadingIdentifiers.remove(id) }
        do {
            // If re-downloading, clear the "removed" mark.
            removedIdentifiers.remove(locale.identifier(.bcp47))
            let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                Log.speech.info("downloading assets for \(locale.identifier, privacy: .public)…")
                try await request.downloadAndInstall()
            }
            await refresh()
        } catch {
            Log.speech.error("asset prepare failed for \(locale.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Releases the asset reservation for the specified locale (UI label: "Remove").
    /// Since the OS performs the actual deletion later, the UI immediately treats it as uninstalled.
    func remove(_ locale: Locale) async {
        removedIdentifiers.insert(locale.identifier(.bcp47))
        _ = await AssetInventory.release(reservedLocale: locale)
        Log.speech.info("released reservation for \(locale.identifier, privacy: .public)")
        await refresh()
    }

    /// Returns whether the settings identifier string matches the specified option's language (normalized comparison using BCP47).
    nonisolated static func matches(_ option: LanguageOption, settingIdentifier: String) -> Bool {
        let a = option.locale.identifier(.bcp47)
        let b = Locale(identifier: settingIdentifier).identifier(.bcp47)
        return a == b
    }

    /// Display name corresponding to the settings identifier.
    nonisolated static func displayName(forIdentifier identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }
}
