//
//  PipelineStatusStore.swift
//  Voxt
//
//  Aggregates pipeline state on the MainActor and reflects it in the menu bar UI.
//  Updated from each actor via await (MainActor hops are acceptable since updates occur per utterance).
//

import Foundation
import Combine
import OSLog

@MainActor
final class PipelineStatusStore: ObservableObject {

    enum UIState: Equatable {
        case ready
        case recording
        /// Processing. queued is the number of utterances remaining in the queue.
        case processing(queued: Int)

        var label: String {
            switch self {
            case .ready: return String(localized: "Ready")
            case .recording: return String(localized: "Recording…")
            case .processing(let n): return n > 0 ? String(localized: "Processing (\(n))") : String(localized: "Processing…")
            }
        }
    }

    @Published private(set) var state: UIState = .ready
    @Published private(set) var lastInsertedSeq: UInt64?
    @Published private(set) var lastError: String?
    /// The most recently inserted text (used for "Copy Last Result").
    @Published private(set) var lastResultText: String?
    /// Whether Foundation Models (Apple Intelligence) is available.
    @Published var modelAvailable = true

    private var enqueuedCount = 0
    private var insertedCount = 0
    private var isRecording = false

    // MARK: - Recording

    func recordingStarted() {
        isRecording = true
        recompute()
    }

    func recordingStopped() {
        isRecording = false
        recompute()
    }

    // MARK: - Pipeline progress (called via await from actors)

    func enqueued() {
        enqueuedCount += 1
        recompute()
    }

    /// Processing of one utterance completed (hook for fine-grained progress display; currently only recomputes state).
    func processed() {
        recompute()
    }

    func inserted(seq: UInt64, text: String? = nil) {
        insertedCount += 1
        lastInsertedSeq = seq
        if let text, !text.isEmpty { lastResultText = text }
        recompute()
    }

    func reportError(_ message: String) {
        lastError = message
        Log.pipeline.error("pipeline error: \(message, privacy: .public)")
    }

    private func recompute() {
        let queued = max(0, enqueuedCount - insertedCount)
        if isRecording {
            state = .recording
        } else if queued > 0 {
            state = .processing(queued: queued)
        } else {
            state = .ready
        }
    }
}
