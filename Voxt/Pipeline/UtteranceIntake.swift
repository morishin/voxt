//
//  UtteranceIntake.swift
//  Voxt
//
//  The entry point that assigns a seq number to each utterance when recording stops and feeds it into the pipeline.
//  By assigning seq numbers synchronously on MainActor, the recording-stop order is strictly guaranteed to match FIFO order.
//

import Foundation

@MainActor
final class UtteranceIntake {
    private var nextRaw: UInt64 = 0
    private let continuation: AsyncStream<RawUtterance>.Continuation

    init(continuation: AsyncStream<RawUtterance>.Continuation) {
        self.continuation = continuation
    }

    /// Call this at the moment recording stops. Immediately assigns a seq number, yields it to the stream, and returns the assigned seq.
    /// The caller can start the next recording immediately after this call.
    @discardableResult
    func submit(audioURL: URL, locale: Locale) -> UtteranceSeq {
        let seq = UtteranceSeq(raw: nextRaw)
        nextRaw += 1
        continuation.yield(RawUtterance(seq: seq, audioURL: audioURL, locale: locale, capturedAt: Date()))
        return seq
    }

    func finish() {
        continuation.finish()
    }
}
