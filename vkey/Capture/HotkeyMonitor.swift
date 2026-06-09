//
//  HotkeyMonitor.swift
//  vkey
//
//  CGEventTap によるグローバルな Push-to-talk キー監視。
//  通常キーは keyDown/keyUp、修飾キー（Right Command 等）は flagsChanged で検出する。
//  auto-repeat は無視する。
//

import CoreGraphics
import OSLog

/// Push-to-talk のキー押下/解放を監視する。
/// コールバックは main run loop 上（= メインスレッド）で呼ばれる。
final class HotkeyMonitor {

    /// 監視対象のキーコード。
    var keyCode: CGKeyCode

    /// キー押下開始（auto-repeat は除外済み）。
    var onPress: (() -> Void)?
    /// キー解放。
    var onRelease: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPressed = false

    init(keyCode: CGKeyCode) {
        self.keyCode = keyCode
    }

    deinit {
        stop()
    }

    /// 監視を開始する。Input Monitoring 権限が無いと tap 作成に失敗し false を返す。
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        // refcon 経由で self を取り出すため、コンテキストを capture しない C 関数にする。
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.capture.error("failed to create event tap (Input Monitoring not granted?)")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        Log.capture.info("hotkey monitor started (keyCode=\(self.keyCode))")
        return true
    }

    /// 監視を停止する。
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        if isPressed {
            isPressed = false
            onRelease?()
        }
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // OS により一時無効化されたら再有効化する。
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }

        case .keyDown:
            guard CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)) == keyCode else { return }
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if isRepeat { return }
            setPressed(true)

        case .keyUp:
            guard CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)) == keyCode else { return }
            setPressed(false)

        case .flagsChanged:
            let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            guard code == keyCode, let modMask = Self.modifierMask(for: keyCode) else { return }
            let down = (event.flags.rawValue & modMask) != 0
            setPressed(down)

        default:
            break
        }
    }

    private func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        if pressed { onPress?() } else { onRelease?() }
    }

    /// 修飾キーの device-dependent マスク。修飾キーでなければ nil。
    static func modifierMask(for keyCode: CGKeyCode) -> UInt64? {
        switch keyCode {
        case 0x37: return 0x08       // Left Command
        case 0x36: return 0x10       // Right Command
        case 0x38: return 0x02       // Left Shift
        case 0x3C: return 0x04       // Right Shift
        case 0x3A: return 0x20       // Left Option
        case 0x3D: return 0x40       // Right Option
        case 0x3B: return 0x01       // Left Control
        case 0x3E: return 0x2000     // Right Control
        case 0x3F: return 0x800000   // Fn (secondary function)
        default: return nil
        }
    }

    /// keyCode を人間可読な名前に。
    static func displayName(for keyCode: CGKeyCode) -> String {
        switch keyCode {
        // 修飾キー
        case 0x37: return "Left Command"
        case 0x36: return "Right Command"
        case 0x38: return "Left Shift"
        case 0x3C: return "Right Shift"
        case 0x3A: return "Left Option"
        case 0x3D: return "Right Option"
        case 0x3B: return "Left Control"
        case 0x3E: return "Right Control"
        case 0x3F: return "Fn"
        // 特殊キー
        case 0x31: return "Space"
        case 0x24: return "Return"
        case 0x30: return "Tab"
        case 0x35: return "Escape"
        case 0x33: return "Delete"
        case 0x39: return "Caps Lock"
        // ファンクションキー
        case 0x7A: return "F1"
        case 0x78: return "F2"
        case 0x63: return "F3"
        case 0x76: return "F4"
        case 0x60: return "F5"
        case 0x61: return "F6"
        case 0x62: return "F7"
        case 0x64: return "F8"
        case 0x65: return "F9"
        case 0x6D: return "F10"
        case 0x67: return "F11"
        case 0x6F: return "F12"
        default:
            if let name = ansiKeyName(for: keyCode) { return name }
            return "Key 0x\(String(keyCode, radix: 16))"
        }
    }

    /// ANSI 配列の英字・数字・記号キーの名前。
    private static func ansiKeyName(for keyCode: CGKeyCode) -> String? {
        let map: [CGKeyCode: String] = [
            0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D", 0x0E: "E", 0x03: "F",
            0x05: "G", 0x04: "H", 0x22: "I", 0x26: "J", 0x28: "K", 0x25: "L",
            0x2E: "M", 0x2D: "N", 0x1F: "O", 0x23: "P", 0x0C: "Q", 0x0F: "R",
            0x01: "S", 0x11: "T", 0x20: "U", 0x09: "V", 0x0D: "W", 0x07: "X",
            0x10: "Y", 0x06: "Z",
            0x1D: "0", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4",
            0x17: "5", 0x16: "6", 0x1A: "7", 0x1C: "8", 0x19: "9",
            0x18: "=", 0x1B: "-", 0x21: "[", 0x1E: "]", 0x29: ";",
            0x27: "'", 0x2B: ",", 0x2F: ".", 0x2C: "/", 0x2A: "\\", 0x32: "`",
        ]
        return map[keyCode]
    }
}
