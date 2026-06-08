//
//  LanguageManager.swift
//  vkey
//
//  対応言語(= Speech が文字起こし可能 ∩ Foundation Models が扱える)を動的に算出し、
//  オンデバイス資産のインストール状態を提供する。言語のクイック切替に使う。
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

        var id: String { locale.identifier }

        /// ローカライズした言語名。
        var displayName: String {
            Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
        }
    }

    @Published private(set) var options: [LanguageOption] = []
    @Published private(set) var isLoading = false

    /// 対応言語リストとインストール状態を再取得する。
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let supported = await SpeechTranscriber.supportedLocales
        let installedIds = Set((await SpeechTranscriber.installedLocales).map { $0.identifier(.bcp47) })
        let model = SystemLanguageModel.default

        let opts: [LanguageOption] = supported
            .filter { model.supportsLocale($0) }
            .map { LanguageOption(locale: $0, isInstalled: installedIds.contains($0.identifier(.bcp47))) }
            .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }

        options = opts
        Log.speech.info("available languages: \(opts.count, privacy: .public)")
    }

    /// 指定 locale の資産をダウンロード・インストールし、状態を更新する。
    func prepare(_ locale: Locale) async {
        do {
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

    /// 設定の identifier 文字列が指定オプションと同一言語か（bcp47 で正規化比較）。
    nonisolated static func matches(_ option: LanguageOption, settingIdentifier: String) -> Bool {
        let a = option.locale.identifier(.bcp47)
        let b = Locale(identifier: settingIdentifier).identifier(.bcp47)
        return a == b
    }

    /// 設定の identifier に対応する表示名。
    nonisolated static func displayName(forIdentifier identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }
}
