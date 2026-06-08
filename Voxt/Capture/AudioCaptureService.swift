//
//  AudioCaptureService.swift
//  Voxt
//
//  Microphone recording via AVAudioEngine. Writes to a temporary file with no persistent storage.
//  Automatically stops after the maximum recording duration.
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

    /// Called when the maximum recording duration is reached (triggers automatic stop).
    var onMaxDurationReached: (() -> Void)?

    private let engine = AVAudioEngine()
    private var currentURL: URL?
    private var isRecording = false
    private var autoStopTask: Task<Void, Never>?

    var recording: Bool { isRecording }

    /// Starts recording and returns the URL of the temporary output file.
    func start(maxSeconds: Double) throws -> URL {
        guard !isRecording else { throw CaptureError.alreadyRecording }

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxt-\(UUID().uuidString).caf")

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forWriting: url, settings: format.settings)
        } catch {
            Log.capture.error("failed to create audio file: \(error.localizedDescription, privacy: .public)")
            throw CaptureError.fileCreateFailed
        }

        // The tap is called on the real-time audio thread. Do not touch self; capture file directly.
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

    /// Stops recording and returns the URL of the written temporary file. Returns nil if not currently recording.
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
