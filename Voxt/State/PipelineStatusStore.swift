//
//  PipelineStatusStore.swift
//  Voxt
//
//  パイプライン状態を MainActor へ集約し、メニューバー UI に反映する。
//  各 actor からは await 経由で更新される（更新頻度は発話単位なので MainActor hop は許容）。
//

import Foundation
import Combine
import OSLog

@MainActor
final class PipelineStatusStore: ObservableObject {

    enum UIState: Equatable {
        case ready
        case recording
        /// 処理中。queued はキューに残っている発話数。
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
    /// 直近に挿入したテキスト（「Last Result をコピー」用）。
    @Published private(set) var lastResultText: String?
    /// Foundation Models（Apple Intelligence）が利用可能か。
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

    // MARK: - Pipeline progress（actor から await 呼び出し）

    func enqueued() {
        enqueuedCount += 1
        recompute()
    }

    /// 1 発話の処理完了（進捗の細分表示用フック。現状は再計算のみ）。
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
