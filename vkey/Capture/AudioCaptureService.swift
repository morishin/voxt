//
//  AudioCaptureService.swift
//  vkey
//
//  AVAudioEngine によるマイク録音。一時ファイルへ書き出し、永続保存はしない。
//  最大録音秒数で自動停止する。
//

import Foundation
import AVFoundation
import OSLog

@MainActor
final class AudioCaptureService {

    enum CaptureError: Error {
        case alreadyRecording
        case fileCreateFailed
        case engineStartFailed
    }

    /// 最大録音秒数に達したときに呼ばれる（自動停止のトリガ）。
    var onMaxDurationReached: (() -> Void)?

    private let engine = AVAudioEngine()
    private var currentURL: URL?
    private var isRecording = false
    private var autoStopTask: Task<Void, Never>?

    var recording: Bool { isRecording }

    /// 録音を開始し、書き出し先の一時ファイル URL を返す。
    func start(maxSeconds: Double) throws -> URL {
        guard !isRecording else { throw CaptureError.alreadyRecording }

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vkey-\(UUID().uuidString).caf")

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forWriting: url, settings: format.settings)
        } catch {
            Log.capture.error("failed to create audio file: \(error.localizedDescription, privacy: .public)")
            throw CaptureError.fileCreateFailed
        }

        // tap はリアルタイム音声スレッドで呼ばれる。self を触らず、file を直接 capture する。
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            try? file.write(from: buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            Log.capture.error("failed to start audio engine: \(error.localizedDescription, privacy: .public)")
            throw CaptureError.engineStartFailed
        }

        currentURL = url
        isRecording = true
        Log.capture.info("recording started")

        scheduleAutoStop(after: maxSeconds)
        return url
    }

    /// 録音を停止し、書き出した一時ファイル URL を返す。録音していなければ nil。
    @discardableResult
    func stop() -> URL? {
        guard isRecording else { return nil }
        autoStopTask?.cancel()
        autoStopTask = nil

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false

        let url = currentURL
        currentURL = nil
        Log.capture.info("recording stopped")
        return url
    }

    private func scheduleAutoStop(after seconds: Double) {
        autoStopTask?.cancel()
        autoStopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.onMaxDurationReached?()
        }
    }
}
