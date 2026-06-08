//
//  GlobalModelLimiter.swift
//  Voxt
//
//  An async semaphore that bounds the concurrency of model calls across all utterances and chunks.
//  Because the on-device model is a single shared resource, the total number of concurrent calls is controlled here.
//  Setting maxConcurrentModelCalls=1 gives fully serial execution (empirical baseline).
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
            // Hand off the permit directly to a waiter (available count stays unchanged).
            let waiter = waiters.removeFirst()
            waiter.resume()
        }
    }

    /// Acquires a permit and executes body. Because body runs outside the actor (in the caller's context),
    /// only concurrency is controlled here while the formatting work itself runs concurrently.
    /// Recursive permit acquisition is prohibited (causes self-deadlock when limit=1).
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
