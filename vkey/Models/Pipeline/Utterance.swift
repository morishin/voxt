//
//  Utterance.swift
//  vkey
//
//  パイプラインを流れる発話のコアデータ型。順序保証の基盤となる seq を含む。
//

import Foundation

/// 単調増加シーケンス番号。採番された瞬間に発話の FIFO 順序が確定する。
struct UtteranceSeq: Hashable, Comparable, Sendable {
    let raw: UInt64
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.raw < rhs.raw }
}

/// 録音停止直後の発話。まだ文字起こしされていない。
struct RawUtterance: Sendable {
    let seq: UtteranceSeq
    /// 録音した一時音声ファイル。文字起こし後に削除する。
    let audioURL: URL
    /// 発話ごとに固定された認識言語。
    let locale: Locale
    let capturedAt: Date
}

/// 1 チャンクの整形結果。index で発話内順序を保持する。
struct FormattedChunk: Sendable {
    let index: Int
    let text: String
}

/// 整形完了または fallback した発話。InsertionSerializer に渡る最終形。
struct ProcessedUtterance: Sendable {
    let seq: UtteranceSeq
    let outcome: Outcome

    enum Outcome: Sendable {
        /// 全チャンク整形に成功して結合済み。
        case formatted(String)
        /// 整形に失敗し、生の文字起こしテキストへ fallback。
        case rawFallback(String, reason: ProcessingError)
        /// 無音など。挿入はスキップするが seq は消費する。
        case empty
    }
}

/// 処理中に起こりうるエラー。Sendable。
enum ProcessingError: Error, Sendable, Equatable {
    case transcriptionFailed(String)
    case modelUnavailable
    /// 分割しても 1 チャンクが収まらなかった。
    case contextWindowExceeded
    case chunkFormattingFailed(index: Int, message: String)
    case cancelled

    var message: String {
        switch self {
        case .transcriptionFailed(let m): return "文字起こし失敗: \(m)"
        case .modelUnavailable: return "言語モデルが利用できません"
        case .contextWindowExceeded: return "コンテキスト上限を超過しました"
        case .chunkFormattingFailed(let i, let m): return "チャンク#\(i) 整形失敗: \(m)"
        case .cancelled: return "キャンセルされました"
        }
    }
}
