//
//  UtteranceIntake.swift
//  Voxt
//
//  録音停止時に seq を採番して発話をパイプラインへ流す入口。
//  採番を MainActor 上で同期的に行うことで、録音停止順 = FIFO 順を厳密に保証する。
//

import Foundation

@MainActor
final class UtteranceIntake {
    private var nextRaw: UInt64 = 0
    private let continuation: AsyncStream<RawUtterance>.Continuation

    init(continuation: AsyncStream<RawUtterance>.Continuation) {
        self.continuation = continuation
    }

    /// 録音停止の瞬間に呼ぶ。seq を即採番して stream に yield し、採番した seq を返す。
    /// 呼び出し側はこの直後にすぐ次の録音を開始できる。
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
