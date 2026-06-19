//
//  TextInserter.swift
//  Voxt
//
//  フォーカス中の UI 要素へテキストを挿入する。Accessibility API による直接挿入を試し、
//  失敗時はクリップボード経由のペースト fallback を行う。
//  挿入は MainActor で 1 件ずつ実行する（InsertionSerializer が seq 順に直列化済み）。
//

import Foundation
import AppKit
import ApplicationServices
import OSLog

/// 挿入の結果。通知・ログに使う。
enum InsertionOutcome: Sendable {
    case directInserted
    case typed
    case pasted
    case failed
}

@MainActor
final class TextInserter {

    /// 指定モードでテキストを挿入し、結果を返す。
    @discardableResult
    func insert(_ text: String, mode: InsertionMode) -> InsertionOutcome {
        guard !text.isEmpty else { return .directInserted }

        switch mode {
        case .direct:
            if insertViaAccessibility(text) { return .directInserted }
            // 直接挿入に失敗したら、手動貼り付けできるようクリップボードへ退避する。
            copyToClipboard(text)
            Log.insertion.error("AX insertion failed (direct mode); copied to clipboard")
            return .failed
        case .paste:
            pasteViaClipboard(text)
            return .pasted
        case .auto:
            // 1) AX 直接挿入（標準テキストフィールド向け。クリップボード非経由）。
            if insertViaAccessibility(text) { return .directInserted }
            // 2) Unicode キーイベントで直接タイプする（Web ビュー/Electron 等の多くのアプリで有効。
            //    クリップボードを一切触らないため、入力テキストがクリップボードに残らない）。
            Log.insertion.info("AX insertion failed; falling back to keyboard typing")
            if typeViaKeyboard(text) { return .typed }
            // 3) どちらも使えない時だけクリップボードへ退避し、手動貼り付けを案内する（ペーストはしない）。
            Log.insertion.error("keyboard typing unavailable; copied to clipboard")
            copyToClipboard(text)
            return .failed
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

    // MARK: - キーボード直接入力（クリップボード非経由）

    /// Unicode 文字列を CGEvent として直接「タイプ」する。クリップボードを使わない。
    /// keyboardSetUnicodeString は 1 イベントに載せる文字数が多いと取りこぼす実装があるため、
    /// 文字単位の小さなチャンクに分けて keyDown/keyUp を投函する。
    /// 現在押されている修飾キーの状態を引き継がないよう privateState のイベントソースを使う。
    private func typeViaKeyboard(_ text: String) -> Bool {
        guard let source = CGEventSource(stateID: .privateState) else { return false }

        // grapheme（Character）単位で分割し、サロゲートペアや結合文字を壊さないようにする。
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

    /// ペーストはせず、クリップボードへ文字列を置くだけ。
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
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
