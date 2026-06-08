//
//  Transcriber.swift
//  Voxt
//
//  Transcribes audio files using the Speech framework (SpeechAnalyzer / SpeechTranscriber).
//  Processes entirely on-device using the specified locale. Required on-device assets are
//  downloaded automatically.
//

import Foundation
import Speech
import AVFoundation
import OSLog

actor Transcriber {

    /// Timeout in seconds for the entire transcription.
    private let timeoutSeconds: Double = 60

    /// Transcribes the audio file at the given URL using the specified locale and returns the finalized text.
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

        // Consume the results stream concurrently (overlapping with the analyzer's processing).
        let resultsTask = Task { try await Self.collect(transcriber) }

        _ = try await analyzer.analyzeSequence(from: audioFile)
        try await analyzer.finalizeAndFinishThroughEndOfInput()

        let transcript = try await resultsTask.value
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Concatenates finalized text from transcriber.results.
    private static func collect(_ transcriber: SpeechTranscriber) async throws -> String {
        var text = AttributedString()
        for try await result in transcriber.results {
            text += result.text
        }
        return String(text.characters)
    }

    /// Returns the supported locale that corresponds to the specified locale.
    static func resolveSupportedLocale(_ locale: Locale) async -> Locale? {
        if let exact = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return exact
        }
        return nil
    }

    /// Downloads and installs required on-device assets if they are not already present.
    private func ensureModelInstalled(for transcriber: SpeechTranscriber) async throws {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            Log.speech.info("downloading speech assets…")
            try await request.downloadAndInstall()
            Log.speech.info("speech assets installed")
        }
    }
}
