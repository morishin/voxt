//
//  InsertionSerializer.swift
//  Voxt
//
//  A re-ordering buffer that strictly serializes insertions in ascending seq order.
//  Even when parallel processing delivers completions out of order, it chain-flushes starting from the item matching nextExpected.
//  Failed and silent utterances also consume a seq, so there are no gaps in ordering and subsequent items are never blocked.
//

import Foundation
import OSLog

actor InsertionSerializer {
    private let inserter: TextInserter
    private let modeProvider: @Sendable () async -> InsertionMode
    private let onInserted: @Sendable (UtteranceSeq, InsertionOutcome?, String) async -> Void

    private var nextExpected: UInt64 = 0
    private var pending: [UInt64: ProcessedUtterance] = [:]

    init(inserter: TextInserter,
         modeProvider: @escaping @Sendable () async -> InsertionMode,
         onInserted: @escaping @Sendable (UtteranceSeq, InsertionOutcome?, String) async -> Void) {
        self.inserter = inserter
        self.modeProvider = modeProvider
        self.onInserted = onInserted
    }

    /// Receives a processed utterance. Inserts it immediately if its turn has come, and chain-flushes any subsequent items that have already arrived.
    func deliver(_ u: ProcessedUtterance) async {
        pending[u.seq.raw] = u
        await drain()
    }

    private func drain() async {
        while let ready = pending[nextExpected] {
            pending[nextExpected] = nil
            await insert(ready)
            nextExpected += 1
        }
    }

    private func insert(_ u: ProcessedUtterance) async {
        switch u.outcome {
        case .formatted(let text), .rawFallback(let text, _):
            if text.isEmpty {
                await onInserted(u.seq, nil, "")
            } else {
                let mode = await modeProvider()
                let outcome = await inserter.insert(text, mode: mode)
                await onInserted(u.seq, outcome, text)
            }
        case .empty:
            // No insertion. The seq is consumed to maintain ordering.
            await onInserted(u.seq, nil, "")
        }
    }
}
