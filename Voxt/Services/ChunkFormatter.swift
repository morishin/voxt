//
//  ChunkFormatter.swift
//  Voxt
//
//  Formats a single chunk using Foundation Models. Runs under a GlobalModelLimiter permit,
//  and on context overflow retries with re-splitting serially while holding the permit.
//

import Foundation
import FoundationModels
import OSLog

struct ChunkFormatter: Sendable {
    let limiter: GlobalModelLimiter
    let chunker: Chunker

    /// Formats a single chunk and returns a FormattedChunk.
    func format(chunkText: String,
                index: Int,
                instructions: String,
                locale: Locale,
                outputSafetyFactor: Double) async throws -> FormattedChunk {
        try await limiter.withPermit {
            try await Self.run(chunkText: chunkText,
                               index: index,
                               instructions: instructions,
                               locale: locale,
                               chunker: chunker,
                               outputSafetyFactor: outputSafetyFactor)
        }
    }

    private static func run(chunkText: String,
                            index: Int,
                            instructions: String,
                            locale: Locale,
                            chunker: Chunker,
                            outputSafetyFactor: Double) async throws -> FormattedChunk {
        let session = LanguageModelSession(instructions: instructions)
        do {
            let prompt = FormattingPromptFactory.prompt(for: chunkText, locale: locale)
            let response = try await session.respond(to: prompt)
            return FormattedChunk(index: index, text: response.content)
        } catch let error as LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = error {
                return try await resplitAndFormat(chunkText: chunkText,
                                                  index: index,
                                                  instructions: instructions,
                                                  locale: locale,
                                                  chunker: chunker,
                                                  outputSafetyFactor: outputSafetyFactor)
            }
            throw ProcessingError.chunkFormattingFailed(index: index, message: "\(error)")
        }
    }

    /// When the token estimate is off and a context overflow occurs, re-splits into smaller pieces,
    /// formats each individually, and joins the results.
    /// Since a permit is already held, this runs serially without acquiring another permit recursively.
    private static func resplitAndFormat(chunkText: String,
                                         index: Int,
                                         instructions: String,
                                         locale: Locale,
                                         chunker: Chunker,
                                         outputSafetyFactor: Double) async throws -> FormattedChunk {
        // Split after subtracting the fixed tokens for the instruction text and prompt wrapper.
        let fixedTokens = Chunker.estimateTokens(instructions)
            + Chunker.estimateTokens(FormattingPromptFactory.prompt(for: "", locale: locale))
        // Increase safety factor to produce smaller splits.
        let sub = chunker.split(transcript: chunkText,
                                locale: locale,
                                instructionTokens: fixedTokens,
                                outputSafetyFactor: outputSafetyFactor + 0.5)
        guard sub.count > 1 else { throw ProcessingError.contextWindowExceeded }

        Log.formatting.info("re-splitting chunk #\(index) into \(sub.count) pieces after context overflow")
        var joined = ""
        for piece in sub {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: FormattingPromptFactory.prompt(for: piece, locale: locale))
            joined += response.content
        }
        return FormattedChunk(index: index, text: joined)
    }
}
