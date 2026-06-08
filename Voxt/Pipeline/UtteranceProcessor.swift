//
//  UtteranceProcessor.swift
//  Voxt
//
//  Processes a single utterance through the pipeline: transcription → chunking → parallel formatting (TaskGroup) → joining in index order.
//  Never throws; failures are folded into ProcessedUtterance.Outcome (to avoid blocking the insertion order of subsequent items).
//

import Foundation
import OSLog

/// A configuration snapshot taken at the time of utterance processing (ensures consistency even if settings change mid-processing).
struct ProcessingConfig: Sendable {
    let formattingMode: FormattingMode
    /// Custom formatting instruction configured by the user (optional; disabled if empty).
    var customInstruction: String = ""
    /// Safety factor for chunk size calculation, assuming output ≈ input length after formatting (internal constant).
    var outputSafetyFactor: Double = 1.15
}

struct UtteranceProcessor: Sendable {
    let transcriber: Transcriber
    let chunker: Chunker
    let formatter: ChunkFormatter

    func process(_ u: RawUtterance, config: ProcessingConfig) async -> ProcessedUtterance {
        // The temporary audio file for the recording must always be deleted upon processing completion (not persisted).
        defer { try? FileManager.default.removeItem(at: u.audioURL) }

        // --- Stage 1: Transcription ---
        let transcript: String
        do {
            transcript = try await transcriber.transcribe(audioURL: u.audioURL, locale: u.locale)
        } catch {
            let reason: ProcessingError = (error as? ProcessingError) ?? .transcriptionFailed("\(error)")
            return ProcessedUtterance(seq: u.seq, outcome: .rawFallback("", reason: reason))
        }

        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ProcessedUtterance(seq: u.seq, outcome: .empty)
        }

        // In raw mode, no model is used; the transcript is used as-is as the final text.
        if config.formattingMode == .raw {
            return ProcessedUtterance(seq: u.seq, outcome: .formatted(transcript))
        }

        // --- Stage 2: Chunking ---
        let instructions = FormattingPromptFactory.instructions(mode: config.formattingMode, locale: u.locale, custom: config.customInstruction)
        // Subtract fixed tokens for the instruction text + prompt wrapper (delimiters, language specification).
        let fixedTokens = Chunker.estimateTokens(instructions)
            + Chunker.estimateTokens(FormattingPromptFactory.prompt(for: "", locale: u.locale))
        let chunks = chunker.split(transcript: transcript,
                                   locale: u.locale,
                                   instructionTokens: fixedTokens,
                                   outputSafetyFactor: config.outputSafetyFactor)

        // --- Stage 3: Format in parallel via TaskGroup, write results back to index positions to restore order ---
        do {
            let formatted = try await withThrowingTaskGroup(of: FormattedChunk.self) { group -> [String] in
                for (i, chunk) in chunks.enumerated() {
                    group.addTask {
                        try await formatter.format(chunkText: chunk,
                                                   index: i,
                                                   instructions: instructions,
                                                   locale: u.locale,
                                                   outputSafetyFactor: config.outputSafetyFactor)
                    }
                }
                var slots = [String?](repeating: nil, count: chunks.count)
                for try await fc in group {
                    slots[fc.index] = fc.text
                }
                return slots.compactMap { $0 }
            }
            // --- Stage 4: Join ---
            return ProcessedUtterance(seq: u.seq, outcome: .formatted(formatted.joined()))
        } catch {
            // If even one chunk fails to format → fall back to the raw transcript for the entire utterance.
            let reason: ProcessingError = (error as? ProcessingError) ?? .chunkFormattingFailed(index: -1, message: "\(error)")
            Log.formatting.error("formatting failed seq=\(u.seq.raw): \(reason.message, privacy: .public)")
            return ProcessedUtterance(seq: u.seq, outcome: .rawFallback(transcript, reason: reason))
        }
    }
}
