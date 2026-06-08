//
//  Transcriber.swift
//  vkey
//
//  Speech framework (SpeechAnalyzer / SpeechTranscriber) による録音ファイルの文字起こし。
//  指定 locale で完全ローカル処理する。必要なオンデバイス資産は自動でダウンロードする。
//

import Foundation
import Speech
import AVFoundation
import OSLog

actor Transcriber {

    /// 文字起こし全体のタイムアウト秒数。
    private let timeoutSeconds: Double = 60

    /// 指定 locale で録音ファイルを文字起こしし、確定テキストを返す。
    func transcribe(audioURL: URL, locale: Locale) async throws -> String {
        let timeout = timeoutSeconds
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await self.performTranscription(audioURL: audioURL, locale: locale)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw ProcessingError.transcriptionFailed("timed out after \(Int(timeout))s")
            }
            guard let result = try await group.next() else {
                throw ProcessingError.transcriptionFailed("no result")
            }
            group.cancelAll()
            return result
        }
    }

    // MARK: - Core

    private func performTranscription(audioURL: URL, locale: Locale) async throws -> String {
        guard let supportedLocale = await Self.resolveSupportedLocale(locale) else {
            throw ProcessingError.transcriptionFailed("locale \(locale.identifier) is not supported")
        }

        let transcriber = SpeechTranscriber(locale: supportedLocale, preset: .transcription)
        try await ensureModelInstalled(for: transcriber)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let audioFile = try AVAudioFile(forReading: audioURL)

        // 結果ストリームを並行に消費する（analyzer の解析と overlap させる）。
        let resultsTask = Task { try await Self.collect(transcriber) }

        _ = try await analyzer.analyzeSequence(from: audioFile)
        try await analyzer.finalizeAndFinishThroughEndOfInput()

        let transcript = try await resultsTask.value
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// transcriber.results から確定テキストを連結する。
    private static func collect(_ transcriber: SpeechTranscriber) async throws -> String {
        var text = AttributedString()
        for try await result in transcriber.results {
            text += result.text
        }
        return String(text.characters)
    }

    /// 指定 locale に対応するサポート済み locale を返す。
    static func resolveSupportedLocale(_ locale: Locale) async -> Locale? {
        if let exact = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return exact
        }
        return nil
    }

    /// 必要なオンデバイス資産が無ければダウンロード・インストールする。
    private func ensureModelInstalled(for transcriber: SpeechTranscriber) async throws {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            Log.speech.info("downloading speech assets…")
            try await request.downloadAndInstall()
            Log.speech.info("speech assets installed")
        }
    }
}
