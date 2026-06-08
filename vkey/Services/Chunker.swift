//
//  Chunker.swift
//  vkey
//
//  文字起こしテキストを、Foundation Models のコンテキスト上限(4096 トークン)に収まる
//  チャンクへ文境界で分割する。整文は出力≈入力なので、入力+出力+指示が上限に収まるよう
//  input budget を計算する。
//
//  トークン数は文字種ベースのヒューリスティックで見積もる（高速）。推定が外れて
//  exceededContextWindowSize が出た場合は ChunkFormatter 側で再分割リトライする二段構え。
//

import Foundation
import NaturalLanguage

struct Chunker: Sendable {

    /// モデルの最大コンテキストサイズ(トークン)。通常 4096。
    let contextSize: Int

    /// 1 チャンクあたりの入力トークン上限。
    /// contextSize = instruction + input + output をすべて含む上限。
    /// 整文は output ≈ input なので input + output ≈ input * (1 + safety)。
    ///   inputBudget = (contextSize - instructionTokens) / (1 + safety) * マージン
    func inputBudget(instructionTokens: Int, outputSafetyFactor: Double) -> Int {
        let usable = Double(max(0, contextSize - instructionTokens))
        let budget = usable / (1.0 + max(0, outputSafetyFactor))
        return max(64, Int(budget * 0.85))
    }

    /// 文(。!? 改行)境界でグリーディに詰めて、各チャンクが budget 以下になるよう分割する。
    func split(transcript: String, locale: Locale, instructionTokens: Int, outputSafetyFactor: Double) -> [String] {
        let budget = inputBudget(instructionTokens: instructionTokens, outputSafetyFactor: outputSafetyFactor)
        let sentences = Self.segmentSentences(transcript, locale: locale)

        var chunks: [String] = []
        var current = ""
        var currentTokens = 0

        for sentence in sentences {
            let tokens = Self.estimateTokens(sentence)
            if tokens > budget {
                // 単文が大きすぎる稀ケース: current を flush してから単文を強制分割。
                if !current.isEmpty { chunks.append(current); current = ""; currentTokens = 0 }
                chunks.append(contentsOf: Self.hardSplit(sentence, budget: budget))
                continue
            }
            if currentTokens + tokens > budget {
                if !current.isEmpty { chunks.append(current) }
                current = sentence
                currentTokens = tokens
            } else {
                current += sentence
                currentTokens += tokens
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks.isEmpty ? [transcript] : chunks
    }

    // MARK: - Sentence segmentation

    nonisolated static func segmentSentences(_ text: String, locale: Locale) -> [String] {
        guard !text.isEmpty else { return [] }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        if let code = locale.language.languageCode?.identifier {
            tokenizer.setLanguage(NLLanguage(rawValue: code))
        }
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let s = String(text[range])
            if !s.isEmpty { sentences.append(s) }
            return true
        }
        return sentences.isEmpty ? [text] : sentences
    }

    /// 1 文字ずつ詰めて budget トークンごとに分割する緊急用 hard split。
    nonisolated static func hardSplit(_ sentence: String, budget: Int) -> [String] {
        var pieces: [String] = []
        var current = ""
        for ch in sentence {
            current.append(ch)
            if estimateTokens(current) >= budget {
                pieces.append(current)
                current = ""
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces.isEmpty ? [sentence] : pieces
    }

    // MARK: - Token estimation

    /// 文字種ベースのトークン数概算。
    /// CJK(日中韓・かな)は約 1 トークン/文字、その他は約 3.5 文字/トークン。
    nonisolated static func estimateTokens(_ s: String) -> Int {
        var cjk = 0
        var other = 0
        for scalar in s.unicodeScalars {
            if isCJK(scalar) { cjk += 1 } else { other += 1 }
        }
        return cjk + Int((Double(other) / 3.5).rounded(.up))
    }

    nonisolated static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF,   // かな
             0x3400...0x4DBF,   // CJK 拡張A
             0x4E00...0x9FFF,   // CJK 統合漢字
             0xAC00...0xD7AF,   // ハングル
             0xF900...0xFAFF:   // CJK 互換漢字
            return true
        default:
            return false
        }
    }
}
