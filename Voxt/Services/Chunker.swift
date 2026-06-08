//
//  Chunker.swift
//  Voxt
//
//  Splits transcribed text into chunks at sentence boundaries so each chunk fits
//  within the Foundation Models context limit (4096 tokens). Since formatting
//  produces output ≈ input, the input budget is calculated so that
//  input + output + instructions all fit within the limit.
//
//  Token counts are estimated with a character-type-based heuristic (fast).
//  If the estimate is off and exceededContextWindowSize is raised, ChunkFormatter
//  handles it with a re-split retry as a second line of defense.
//

import Foundation
import NaturalLanguage

struct Chunker: Sendable {

    /// Maximum context size of the model in tokens. Typically 4096.
    let contextSize: Int

    /// Maximum input token budget per chunk.
    /// contextSize is the upper limit including all of: instructions + input + output.
    /// Since formatting gives output ≈ input, input + output ≈ input * (1 + safety).
    ///   inputBudget = (contextSize - instructionTokens) / (1 + safety) * margin
    func inputBudget(instructionTokens: Int, outputSafetyFactor: Double) -> Int {
        let usable = Double(max(0, contextSize - instructionTokens))
        let budget = usable / (1.0 + max(0, outputSafetyFactor))
        return max(64, Int(budget * 0.85))
    }

    /// Greedily packs text at sentence (。!? newline) boundaries so each chunk stays within the budget.
    func split(transcript: String, locale: Locale, instructionTokens: Int, outputSafetyFactor: Double) -> [String] {
        let budget = inputBudget(instructionTokens: instructionTokens, outputSafetyFactor: outputSafetyFactor)
        let sentences = Self.segmentSentences(transcript, locale: locale)

        var chunks: [String] = []
        var current = ""
        var currentTokens = 0

        for sentence in sentences {
            let tokens = Self.estimateTokens(sentence)
            if tokens > budget {
                // Rare case where a single sentence is too large: flush current, then hard-split the sentence.
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

    /// Emergency hard split: fills character by character and splits every budget tokens.
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

    /// Rough token count estimate based on character type.
    /// CJK (Chinese/Japanese/Korean, kana) ≈ 1 token/character; others ≈ 3.5 characters/token.
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
        case 0x3040...0x30FF,   // Kana
             0x3400...0x4DBF,   // CJK Extension A
             0x4E00...0x9FFF,   // CJK Unified Ideographs
             0xAC00...0xD7AF,   // Hangul
             0xF900...0xFAFF:   // CJK Compatibility Ideographs
            return true
        default:
            return false
        }
    }
}
