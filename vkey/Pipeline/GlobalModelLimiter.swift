//
//  GlobalModelLimiter.swift
//  vkey
//
//  全発話・全チャンクにまたがるモデル呼び出しの並列度をバウンドする async セマフォ。
//  on-device モデルは単一共有リソースなので、同時呼び出し総数をここで制御する。
//  maxConcurrentModelCalls=1 で完全直列(実測ベースライン)。
//

import Foundation

actor GlobalModelLimiter {
    private let limit: Int
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrentModelCalls: Int) {
        let n = max(1, maxConcurrentModelCalls)
        self.limit = n
        self.available = n
    }

    private func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            available = min(limit, available + 1)
        } else {
            // permit を待機者へ直接 hand-off（available は据え置き）。
            let waiter = waiters.removeFirst()
            waiter.resume()
        }
    }

    /// permit を取得して body を実行する。body は actor 外（呼び出し元コンテキスト）で
    /// 動くため、ここで並列度のみを制御し、整形処理自体は並行に走る。
    /// permit の再帰取得は禁止（limit=1 で自己デッドロックする）。
    nonisolated func withPermit<T>(_ body: () async throws -> T) async rethrows -> T {
        await acquire()
        do {
            let result = try await body()
            await release()
            return result
        } catch {
            await release()
            throw error
        }
    }
}
