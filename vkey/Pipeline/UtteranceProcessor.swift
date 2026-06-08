//
//  UtteranceProcessor.swift
//  vkey
//
//  1 発話を「文字起こし → チャンク分割 → 並列整形(TaskGroup) → index 順結合」で処理する。
//  決して throw せず、失敗は ProcessedUtterance.Outcome に畳む（後続の挿入順をブロックしないため）。
//

import Foundation
import OSLog

/// 発話処理時の設定スナップショット（処理中に設定が変わっても一貫させる）。
struct ProcessingConfig: Sendable {
    let formattingMode: FormattingMode
    let outputSafetyFactor: Double
}

struct UtteranceProcessor: Sendable {
    let transcriber: Transcriber
    let chunker: Chunker
    let formatter: ChunkFormatter

    func process(_ u: RawUtterance, config: ProcessingConfig) async -> ProcessedUtterance {
        // 録音の一時ファイルは処理完了時に必ず削除する（永続保存しない）。
        defer { try? FileManager.default.removeItem(at: u.audioURL) }

        // --- Stage 1: 文字起こし ---
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

        // raw モードはモデルを使わず、そのまま最終テキストとする。
        if config.formattingMode == .raw {
            return ProcessedUtterance(seq: u.seq, outcome: .formatted(transcript))
        }

        // --- Stage 2: チャンク分割 ---
        let instructions = FormattingPromptFactory.instructions(mode: config.formattingMode, locale: u.locale)
        let instructionTokens = Chunker.estimateTokens(instructions)
        let chunks = chunker.split(transcript: transcript,
                                   locale: u.locale,
                                   instructionTokens: instructionTokens,
                                   outputSafetyFactor: config.outputSafetyFactor)

        // --- Stage 3: TaskGroup で並列整形し、index 位置へ書き戻して順序復元 ---
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
            // --- Stage 4: 結合 ---
            return ProcessedUtterance(seq: u.seq, outcome: .formatted(formatted.joined()))
        } catch {
            // どれか 1 チャンクでも整形不能 → 発話全体を生 transcript へ fallback。
            let reason: ProcessingError = (error as? ProcessingError) ?? .chunkFormattingFailed(index: -1, message: "\(error)")
            Log.formatting.error("formatting failed seq=\(u.seq.raw): \(reason.message, privacy: .public)")
            return ProcessedUtterance(seq: u.seq, outcome: .rawFallback(transcript, reason: reason))
        }
    }
}
