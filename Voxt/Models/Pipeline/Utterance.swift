//
//  Utterance.swift
//  Voxt
//
//  Core data types for utterances flowing through the pipeline. Includes seq, which is the basis for ordering guarantees.
//

import Foundation

/// Monotonically increasing sequence number. The FIFO order of an utterance is fixed the moment it is assigned.
struct UtteranceSeq: Hashable, Comparable, Sendable {
    let raw: UInt64
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.raw < rhs.raw }
}

/// An utterance immediately after recording stops. Not yet transcribed.
struct RawUtterance: Sendable {
    let seq: UtteranceSeq
    /// Temporary audio file recorded. Deleted after transcription.
    let audioURL: URL
    /// Recognition locale fixed per utterance.
    let locale: Locale
    let capturedAt: Date
}

/// Formatting result for one chunk. index preserves the order within an utterance.
struct FormattedChunk: Sendable {
    let index: Int
    let text: String
}

/// An utterance that has completed formatting or fallen back. The final form passed to InsertionSerializer.
struct ProcessedUtterance: Sendable {
    let seq: UtteranceSeq
    let outcome: Outcome

    enum Outcome: Sendable {
        /// All chunks formatted successfully and joined.
        case formatted(String)
        /// Formatting failed; fell back to the raw transcription text.
        case rawFallback(String, reason: ProcessingError)
        /// Silence or similar. Insertion is skipped but seq is consumed.
        case empty
    }
}

/// Errors that can occur during processing. Sendable.
enum ProcessingError: Error, Sendable, Equatable {
    case transcriptionFailed(String)
    case modelUnavailable
    /// Even after splitting, a single chunk did not fit.
    case contextWindowExceeded
    case chunkFormattingFailed(index: Int, message: String)
    case cancelled

    var message: String {
        switch self {
        case .transcriptionFailed(let m): return "Transcription failed: \(m)"
        case .modelUnavailable: return "Language model is unavailable"
        case .contextWindowExceeded: return "Context window exceeded"
        case .chunkFormattingFailed(let i, let m): return "Chunk #\(i) formatting failed: \(m)"
        case .cancelled: return "Cancelled"
        }
    }
}
