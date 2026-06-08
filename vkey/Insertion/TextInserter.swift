//
//  TextInserter.swift
//  vkey
//
//  フォーカス中の UI 要素へテキストを挿入する。Accessibility API による直接挿入を試し、
//  失敗時はクリップボード経由のペースト fallback を行う。
//  挿入は MainActor で 1 件ずつ実行する（InsertionSerializer が seq 順に直列化済み）。
//

import Foundation
import AppKit
import ApplicationServices
import OSLog

@MainActor
final class TextInserter {

    /// 指定モードでテキストを挿入する。
    func insert(_ text: String, mode: InsertionMode) {
        guard !text.isEmpty else { return }

        switch mode {
        case .direct:
            if !insertViaAccessibility(text) {
                Log.insertion.error("AX insertion failed (direct mode); text left uninserted")
            }
        case .paste:
            pasteViaClipboard(text)
        case .auto:
            if !insertViaAccessibility(text) {
                Log.insertion.info("AX insertion failed; falling back to clipboard paste")
                pasteViaClipboard(text)
            }
        }
    }

    // MARK: - Accessibility 直接挿入

    private func insertViaAccessibility(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let copyErr = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard copyErr == .success, let focused = focusedRef else { return false }

        // CFTypeRef を AXUIElement として扱う。
        let element = focused as! AXUIElement

        // kAXSelectedText を設定すると、選択範囲を置換 or カーソル位置へ挿入できる。
        var settable: DarwinBoolean = false
        let settableErr = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable)
        guard settableErr == .success, settable.boolValue else { return false }

        let setErr = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
        return setErr == .success
    }

    // MARK: - クリップボード fallback

    private func pasteViaClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        // 既存の文字列内容を退避し、ペースト後に復元する。
        let previous = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        synthesizeCommandV()

        // 少し遅延してから元のクリップボードを復元する。
        if let previous {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                self?.restoreClipboard(previous)
            }
        }
    }

    private func restoreClipboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    /// Cmd-V を合成してペーストする（Accessibility 権限が必要）。
    private func synthesizeCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09 // 'v'
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
            Log.insertion.error("failed to create paste key events")
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }
}
