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
        /// 削除ボタンを出してよいか。システム言語（OS 管理で消せない）は false。
        let isRemovable: Bool

        var id: String { locale.identifier }

        /// ローカライズした言語名。
        var displayName: String {
            Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
        }
    }

    @Published private(set) var options: [LanguageOption] = []
    @Published private(set) var isLoading = false
    /// ダウンロード中の locale identifier 集合。
    @Published private(set) var downloadingIdentifiers: Set<String> = []
    /// 「削除」した（予約解除した）言語の bcp47 id。release 後も installedLocales に
    /// 当面残ることがあるため、UI 上は即座に未インストール扱いへ倒すのに使う。
    private var removedIdentifiers: Set<String> = []

    /// ダウンロード済みの言語のみ。
    var installedOptions: [LanguageOption] { options.filter(\.isInstalled) }

    func isDownloading(_ option: LanguageOption) -> Bool {
        downloadingIdentifiers.contains(option.locale.identifier)
    }

    /// 対応言語リストとインストール状態を再取得する。
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let supported = await SpeechTranscriber.supportedLocales
        let installedIds = Set((await SpeechTranscriber.installedLocales).map { $0.identifier(.bcp47) })
        // システム言語は OS 管理で削除できないため、削除ボタンを出さない。
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

    /// 指定 locale の資産をダウンロード・インストールし、状態を更新する。
    func prepare(_ locale: Locale) async {
        let id = locale.identifier
        downloadingIdentifiers.insert(id)
        defer { downloadingIdentifiers.remove(id) }
        do {
            // 再ダウンロードなら「削除済み」マークを解除する。
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

    /// 指定 locale のアセット予約を解除する（UI ラベルは「削除」）。
    /// 実体の削除は OS が後から行うため、UI 上は即座に未インストール扱いにする。
    func remove(_ locale: Locale) async {
        removedIdentifiers.insert(locale.identifier(.bcp47))
        _ = await AssetInventory.release(reservedLocale: locale)
        Log.speech.info("released reservation for \(locale.identifier, privacy: .public)")
        await refresh()
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
