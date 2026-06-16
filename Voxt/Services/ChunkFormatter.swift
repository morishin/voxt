//
//  ChunkFormatter.swift
//  Voxt
//
//  1 チャンクを Foundation Models で整形する。GlobalModelLimiter の permit 下で実行し、
//  コンテキスト超過時は permit を保持したまま直列で再分割リトライする。
//

import Foundation
import FoundationModels
import OSLog

struct ChunkFormatter: Sendable {
    let limiter: GlobalModelLimiter
    let chunker: Chunker

    /// 1 チャンクを整形して FormattedChunk を返す。
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

    /// 推定が外れてコンテキスト超過した場合、より小さく再分割して個別整形し結合する。
    /// 既に permit を保持しているので、ここでは再帰的に permit を取得せず直列実行する。
    private static func resplitAndFormat(chunkText: String,
                                         index: Int,
                                         instructions: String,
                                         locale: Locale,
                                         chunker: Chunker,
                                         outputSafetyFactor: Double) async throws -> FormattedChunk {
        // 指示文 + プロンプト包装分の固定トークンを差し引いて分割する。
        let fixedTokens = Chunker.estimateTokens(instructions)
            + Chunker.estimateTokens(FormattingPromptFactory.prompt(for: "", locale: locale))
        // safety を増やしてより小さく分割する。
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
