//
//  InsertionSerializer.swift
//  vkey
//
//  挿入を厳密に seq 昇順で直列化する re-ordering バッファ。
//  並列処理で完了順がバラバラに届いても、nextExpected と一致するものから連鎖 flush する。
//  失敗発話・無音発話も seq を消費するため、順序に穴が空かず後続をブロックしない。
//

import Foundation
import OSLog

actor InsertionSerializer {
    private let inserter: TextInserter
    private let modeProvider: @Sendable () async -> InsertionMode
    private let onInserted: @Sendable (UtteranceSeq) async -> Void

    private var nextExpected: UInt64 = 0
    private var pending: [UInt64: ProcessedUtterance] = [:]

    init(inserter: TextInserter,
         modeProvider: @escaping @Sendable () async -> InsertionMode,
         onInserted: @escaping @Sendable (UtteranceSeq) async -> Void) {
        self.inserter = inserter
        self.modeProvider = modeProvider
        self.onInserted = onInserted
    }

    /// 処理完了した発話を受け取る。順番が来ていれば即挿入し、後続が既に届いていれば連鎖 flush する。
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
            if !text.isEmpty {
                let mode = await modeProvider()
                await inserter.insert(text, mode: mode)
            }
        case .empty:
            break // 挿入なし。seq は消費して順序を維持する。
        }
        await onInserted(u.seq)
    }
}
