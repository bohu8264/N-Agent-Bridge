import Air75AgentBridgeCore
import AppKit
import ApplicationServices
import Foundation

/// Prevents the board-profile events from continuing into macOS after they
/// have been consumed by the Air75 HID listener. F13-F15 are especially
/// important because macOS treats F14/F15 as display-brightness keys.
final class DedicatedKeyEventSuppressor: @unchecked Sendable {
    private let lock = NSLock()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var enabled = false
    private var suppressedCount = 0
    private var learnedVirtualKeyCodes = Set<Int64>()

    private static let dedicatedVirtualKeyCodes: Set<Int64> = [
        0x69, // F13 / Print Screen
        0x6B, // F14 / Scroll Lock
        0x71, // F15 / Pause
        0x6A, // F16
        0x40, // F17
        0x4F, // F18
        0x50, // F19
        0x5A  // F20
    ]
    private static let f13Character = UnicodeScalar(0xF710)!
    private static let f24Character = UnicodeScalar(0xF71B)!

    @discardableResult
    func setEnabled(_ value: Bool, keyBindings: [KeyBinding] = []) -> Bool {
        lock.lock()
        enabled = value
        learnedVirtualKeyCodes = Set(keyBindings.compactMap(Self.virtualKeyCode(for:)))
        lock.unlock()

        if value {
            startIfNeeded()
        } else {
            stop()
        }
        return isRunning
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return eventTap != nil
    }

    private func startIfNeeded() {
        guard !isRunning else { return }
        let types: [CGEventType] = [.keyDown, .keyUp]
        let mask = types.reduce(CGEventMask(0)) { partial, type in
            partial | (CGEventMask(1) << type.rawValue)
        }
        guard let tap = CGEvent.tapCreate(
            // A session tap is the earliest public, non-root tap that can
            // suppress events. A HID-location tap is root-only on macOS.
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            publishState(running: false, reason: "无法创建专用按键拦截器；请检查输入监控和辅助功能权限")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        lock.lock()
        eventTap = tap
        runLoopSource = source
        lock.unlock()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        publishState(running: true, reason: "Air75 专用事件已从 macOS 系统功能中隔离")
    }

    private func stop() {
        lock.lock()
        let tap = eventTap
        let source = runLoopSource
        eventTap = nil
        runLoopSource = nil
        lock.unlock()
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        publishState(running: false, reason: "专用按键拦截器已停止")
    }

    private func shouldSuppress(_ type: CGEventType, event: CGEvent) -> Bool {
        lock.lock()
        let isEnabled = enabled
        lock.unlock()
        guard isEnabled, type == .keyDown || type == .keyUp else { return false }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if Self.dedicatedVirtualKeyCodes.contains(keyCode) { return true }
        lock.lock()
        let isLearnedKey = learnedVirtualKeyCodes.contains(keyCode)
        lock.unlock()
        if isLearnedKey { return true }

        // Carbon only publishes virtual-key constants through F20. AppKit
        // still exposes F21-F24 as private-use function-key characters.
        guard let characters = NSEvent(cgEvent: event)?.charactersIgnoringModifiers,
              let scalar = characters.unicodeScalars.first else { return false }
        return scalar.value >= Self.f13Character.value && scalar.value <= Self.f24Character.value
    }

    private func didSuppress(_ type: CGEventType, event: CGEvent) {
        lock.lock()
        suppressedCount += 1
        let count = suppressedCount
        lock.unlock()
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        DispatchQueue.main.async {
            UserDefaults.standard.set(true, forKey: "DedicatedEventSuppressionActive")
            UserDefaults.standard.set(count, forKey: "DedicatedEventSuppressedCount")
            UserDefaults.standard.set(keyCode, forKey: "LastSuppressedVirtualKeyCode")
            UserDefaults.standard.set(type.rawValue, forKey: "LastSuppressedEventType")
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "LastSuppressedEventAt")
        }
    }

    private func reenableAfterSystemDisable() {
        lock.lock()
        let tap = eventTap
        let shouldEnable = enabled
        lock.unlock()
        if let tap, shouldEnable { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    private func publishState(running: Bool, reason: String) {
        DispatchQueue.main.async {
            UserDefaults.standard.set(running, forKey: "DedicatedEventSuppressionActive")
            UserDefaults.standard.set(reason, forKey: "DedicatedEventSuppressionStatus")
        }
    }

    /// USB HID keyboard usage -> macOS ANSI virtual key code. This covers the
    /// normal alphanumeric, punctuation, F-row and navigation keys exposed by
    /// the learning UI. Media/consumer usages are deliberately excluded because
    /// a regular keyboard event tap cannot suppress them reliably.
    private static func virtualKeyCode(for binding: KeyBinding) -> Int64? {
        guard binding.isSupportedInputSource else { return nil }
        let map: [Int: Int64] = [
            0x04: 0x00, 0x05: 0x0B, 0x06: 0x08, 0x07: 0x02, 0x08: 0x0E,
            0x09: 0x03, 0x0A: 0x05, 0x0B: 0x04, 0x0C: 0x22, 0x0D: 0x26,
            0x0E: 0x28, 0x0F: 0x25, 0x10: 0x2E, 0x11: 0x2D, 0x12: 0x1F,
            0x13: 0x23, 0x14: 0x0C, 0x15: 0x0F, 0x16: 0x01, 0x17: 0x11,
            0x18: 0x20, 0x19: 0x09, 0x1A: 0x0D, 0x1B: 0x07, 0x1C: 0x10,
            0x1D: 0x06,
            0x1E: 0x12, 0x1F: 0x13, 0x20: 0x14, 0x21: 0x15, 0x22: 0x17,
            0x23: 0x16, 0x24: 0x1A, 0x25: 0x1C, 0x26: 0x19, 0x27: 0x1D,
            0x28: 0x24, 0x29: 0x35, 0x2A: 0x33, 0x2B: 0x30, 0x2C: 0x31,
            0x2D: 0x1B, 0x2E: 0x18, 0x2F: 0x21, 0x30: 0x1E, 0x31: 0x2A,
            0x33: 0x29, 0x34: 0x27, 0x35: 0x32, 0x36: 0x2B, 0x37: 0x2F,
            0x38: 0x2C, 0x39: 0x39,
            0x3A: 0x7A, 0x3B: 0x78, 0x3C: 0x63, 0x3D: 0x76, 0x3E: 0x60,
            0x3F: 0x61, 0x40: 0x62, 0x41: 0x64, 0x42: 0x65, 0x43: 0x6D,
            0x44: 0x67, 0x45: 0x6F,
            0x46: 0x69, 0x47: 0x6B, 0x48: 0x71, 0x49: 0x72, 0x4A: 0x73,
            0x4B: 0x74, 0x4C: 0x75, 0x4D: 0x77, 0x4E: 0x79, 0x4F: 0x7C,
            0x50: 0x7B, 0x51: 0x7D, 0x52: 0x7E,
            0x53: 0x47, 0x54: 0x4B, 0x55: 0x43, 0x56: 0x4E, 0x57: 0x45,
            0x58: 0x4C, 0x59: 0x53, 0x5A: 0x54, 0x5B: 0x55, 0x5C: 0x56,
            0x5D: 0x57, 0x5E: 0x58, 0x5F: 0x59, 0x60: 0x5B, 0x61: 0x5C,
            0x62: 0x52, 0x63: 0x41
        ]
        return map[binding.usage]
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let suppressor = Unmanaged<DedicatedKeyEventSuppressor>.fromOpaque(userInfo).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            suppressor.reenableAfterSystemDisable()
            return Unmanaged.passUnretained(event)
        }
        if suppressor.shouldSuppress(type, event: event) {
            suppressor.didSuppress(type, event: event)
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}
