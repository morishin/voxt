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
        case 0x37: return "Left Command"
        case 0x36: return "Right Command"
        case 0x38: return "Left Shift"
        case 0x3C: return "Right Shift"
        case 0x3A: return "Left Option"
        case 0x3D: return "Right Option"
        case 0x3B: return "Left Control"
        case 0x3E: return "Right Control"
        case 0x3F: return "Fn"
        default: return "Key 0x\(String(keyCode, radix: 16))"
        }
    }
}
