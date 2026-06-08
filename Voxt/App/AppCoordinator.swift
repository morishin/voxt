//
//  AppCoordinator.swift
//  Voxt
//
//  Central wiring for the entire app. Ties together permissions, hotkey, recording, intake, and (in later phases) formatting and insertion.
//

import Foundation
import Combine
import CoreGraphics
import AppKit
import FoundationModels
import ServiceManagement
import OSLog

@MainActor
final class AppCoordinator: ObservableObject {

    let settings: SettingsStore
    let status: PipelineStatusStore
    let permissions: PermissionManager
    let languages = LanguageManager()

    private let hotkey: HotkeyMonitor
    private let capture = AudioCaptureService()
    private let intake: UtteranceIntake
    private let utteranceStream: AsyncStream<RawUtterance>
    private let transcriber = Transcriber()

    private var pipelineTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(settings: SettingsStore, status: PipelineStatusStore) {
        self.settings = settings
        self.status = status
        self.permissions = PermissionManager()
        self.hotkey = HotkeyMonitor(keyCode: CGKeyCode(settings.hotKeyKeyCode))

        let (stream, continuation) = AsyncStream<RawUtterance>.makeStream()
        self.utteranceStream = stream
        self.intake = UtteranceIntake(continuation: continuation)

        configureHotkey()
        configureCapture()
        observeSettings()
    }

    /// Called at launch. Starts permission checks, hotkey monitoring, and the processing pipeline.
    func start() {
        permissions.refresh()
        // Accessibility will not appear in System Settings until AXIsProcessTrustedWithOptions(prompt:)
        // is called at least once (the app won't be listed until recording→insertion is attempted).
        // If not granted at launch, show the prompt once to register and guide the user.
        if !permissions.accessibility.isGranted {
            permissions.requestAccessibility()
        }
        hotkey.start()
        status.modelAvailable = SystemLanguageModel.default.isAvailable
        applyLaunchAtLogin(settings.launchAtLogin)
        startPipeline()
        Task {
            await languages.refresh()
        }
    }

    /// Copies the most recently inserted text to the clipboard (used for the menu's Last Result item).
    func copyLastResult() {
        guard let text = status.lastResultText, !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Hotkey

    private func configureHotkey() {
        hotkey.onPress = { [weak self] in
            MainActor.assumeIsolated { self?.startRecording() }
        }
        hotkey.onRelease = { [weak self] in
            MainActor.assumeIsolated { self?.stopRecordingAndSubmit() }
        }
    }

    private func configureCapture() {
        capture.onMaxDurationReached = { [weak self] in
            MainActor.assumeIsolated { self?.stopRecordingAndSubmit() }
        }
    }

    private func observeSettings() {
        settings.$hotKeyKeyCode
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] newCode in
                self?.updateHotKey(keyCode: newCode)
            }
            .store(in: &cancellables)

        settings.$launchAtLogin
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] enabled in
                self?.applyLaunchAtLogin(enabled)
            }
            .store(in: &cancellables)
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("failed to update login item: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func updateHotKey(keyCode: Int) {
        hotkey.stop()
        hotkey.keyCode = CGKeyCode(keyCode)
        hotkey.start()
    }

    // MARK: - Recording

    /// Recordings shorter than this duration are treated as accidental taps and discarded.
    private let minRecordingSeconds: TimeInterval = 0.3
    /// Safety ceiling to prevent recording from running indefinitely due to missed keyUp events, etc. (not a user setting).
    private let maxRecordingSeconds: TimeInterval = 300
    private var recordingStartedAt: Date?

    private func startRecording() {
        guard !capture.recording else { return }
        do {
            _ = try capture.start(maxSeconds: maxRecordingSeconds)
            recordingStartedAt = Date()
            status.recordingStarted()
        } catch {
            status.reportError("Failed to start recording: \(error)")
        }
    }

    private func stopRecordingAndSubmit() {
        let url = capture.stop()
        let elapsed = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? .infinity
        recordingStartedAt = nil
        status.recordingStopped()
        guard let url else { return }

        // Discard recordings that are too short (accidental taps) to avoid unnecessary transcription and processing flashes.
        if elapsed < minRecordingSeconds {
            Log.capture.info("discarding too-short recording (\(elapsed, format: .fixed(precision: 2))s)")
            try? FileManager.default.removeItem(at: url)
            return
        }

        let locale = Locale(identifier: settings.defaultLanguageIdentifier)
        intake.submit(audioURL: url, locale: locale)
        // Reflect the newly enqueued utterance in the pending queue count (decremented when insertion completes).
        status.enqueued()
    }

    // MARK: - Pipeline

    private func startPipeline() {
        let maxModelCalls = settings.maxConcurrentModelCalls
        let maxUtterances = settings.maxConcurrentUtterances
        let status = self.status

        pipelineTask = Task { [utteranceStream, transcriber, settings] in
            // Build the processing stack once (GlobalModelLimiter is shared across all utterances).
            let contextSize = SystemLanguageModel.default.contextSize
            let chunker = Chunker(contextSize: contextSize)
            let limiter = GlobalModelLimiter(maxConcurrentModelCalls: maxModelCalls)
            let formatter = ChunkFormatter(limiter: limiter, chunker: chunker)
            let processor = UtteranceProcessor(transcriber: transcriber, chunker: chunker, formatter: formatter)

            let inserter = TextInserter()
            let serializer = InsertionSerializer(
                inserter: inserter,
                modeProvider: { .auto }, // Insertion mode is always auto (direct insertion → paste on failure).
                onInserted: { seq, outcome, text in
                    await status.inserted(seq: seq.raw, text: text.isEmpty ? nil : text)
                    // Only show an alert when insertion fails completely (pasted counts as success, so no notification).
                    if case .failed = outcome {
                        await MainActor.run { Self.showInsertionFailedAlert() }
                    }
                }
            )
            let coordinator = PipelineCoordinator(
                processor: processor,
                serializer: serializer,
                configProvider: { await Self.makeConfig(from: settings) }
            )

            await coordinator.run(stream: utteranceStream, maxConcurrentUtterances: maxUtterances)
        }
    }

    /// Creates a processing config snapshot from MainActor settings. Falls back to raw mode when the model is unavailable.
    private static func makeConfig(from settings: SettingsStore) async -> ProcessingConfig {
        await MainActor.run {
            let modelAvailable = SystemLanguageModel.default.isAvailable
            let mode = modelAvailable ? settings.formattingMode : .raw
            return ProcessingConfig(formattingMode: mode, customInstruction: settings.customFormattingInstruction)
        }
    }

    /// Warning alert displayed when text insertion fails completely.
    @MainActor
    private static func showInsertionFailedAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Couldn't insert text")
        alert.informativeText = String(localized: "The text was saved to the clipboard. Select where you want it and paste with ⌘V.")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
