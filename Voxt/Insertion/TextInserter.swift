//
//  TextInserter.swift
//  Voxt
//
//  Inserts text into the focused UI element. Attempts direct insertion via the Accessibility API,
//  and falls back to clipboard-based paste on failure.
//  Insertions are executed one at a time on the MainActor (serialized in sequence order by InsertionSerializer).
//

import Foundation
import AppKit
import ApplicationServices
import OSLog

/// The result of an insertion. Used for notifications and logging.
enum InsertionOutcome: Sendable {
    case directInserted
    case typed
    case pasted
    case failed
}

@MainActor
final class TextInserter {

    /// Inserts text in the specified mode and returns the result.
    @discardableResult
    func insert(_ text: String, mode: InsertionMode) -> InsertionOutcome {
        guard !text.isEmpty else { return .directInserted }

        switch mode {
        case .direct:
            if insertViaAccessibility(text) { return .directInserted }
            // If direct insertion fails, copy to clipboard so the user can paste manually.
            copyToClipboard(text)
            Log.insertion.error("AX insertion failed (direct mode); copied to clipboard")
            return .failed
        case .paste:
            pasteViaClipboard(text)
            return .pasted
        case .auto:
            // 1) Direct AX insertion (for standard text fields; does not use the clipboard).
            if insertViaAccessibility(text) { return .directInserted }
            // 2) Type directly via Unicode key events (works for many apps including web views/Electron etc.;
            //    does not touch the clipboard at all, so the input text does not remain on the clipboard).
            Log.insertion.info("AX insertion failed; falling back to keyboard typing")
            if typeViaKeyboard(text) { return .typed }
            // 3) Only when neither works, copy to clipboard and guide the user to paste manually (does not paste).
            Log.insertion.error("keyboard typing unavailable; copied to clipboard")
            copyToClipboard(text)
            return .failed
        }
    }

    // MARK: - Accessibility direct insertion

    private func insertViaAccessibility(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let copyErr = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard copyErr == .success, let focused = focusedRef else { return false }

        // Treat the CFTypeRef as an AXUIElement.
        let element = focused as! AXUIElement

        // Setting kAXSelectedText replaces the selection or inserts at the cursor position.
        var settable: DarwinBoolean = false
        let settableErr = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable)
        guard settableErr == .success, settable.boolValue else { return false }

        let setErr = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
        return setErr == .success
    }

    // MARK: - Direct keyboard input (without clipboard)

    /// Directly "types" a Unicode string as CGEvents. Does not use the clipboard.
    /// Since some implementations drop characters when too many are packed into a single event,
    /// the string is split into small character-sized chunks and keyDown/keyUp events are posted per chunk.
    /// Uses a privateState event source to avoid inheriting the state of currently held modifier keys.
    private func typeViaKeyboard(_ text: String) -> Bool {
        guard let source = CGEventSource(stateID: .privateState) else { return false }

        // Split by grapheme (Character) units to avoid breaking surrogate pairs or combining characters.
        let chunkSize = 16
        var index = text.startIndex
        while index < text.endIndex {
            let end = text.index(index, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
            var utf16 = Array(text[index..<end].utf16)
            index = end

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                return false
            }
            keyDown.flags = []
            keyUp.flags = []
            keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            keyDown.post(tap: .cgAnnotatedSessionEventTap)
            keyUp.post(tap: .cgAnnotatedSessionEventTap)
        }
        return true
    }

    // MARK: - Clipboard fallback

    private func pasteViaClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        // Save the existing string content and restore it after pasting.
        let previous = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        synthesizeCommandV()

        // Restore the original clipboard contents after a short delay.
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

    /// Only places the string onto the clipboard without pasting.
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Synthesizes Cmd-V to paste (requires Accessibility permission).
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
