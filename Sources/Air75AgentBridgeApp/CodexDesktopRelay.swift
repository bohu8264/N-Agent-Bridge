import AppKit
import ApplicationServices
import Air75AgentBridgeCore

@MainActor
final class CodexDesktopRelay {
    static let eventSourceTag: Int64 = 0x4149_5237_3543_4458
    enum RelayError: LocalizedError {
        case accessibilityDenied
        case codexNotRunning
        case eventCreationFailed

        var errorDescription: String? {
            switch self {
            case .accessibilityDenied: return "需要在系统设置中允许 N Agent Bridge 使用辅助功能"
            case .codexNotRunning: return "Codex Desktop 尚未运行"
            case .eventCreationFailed: return "无法创建发送给 Codex 的键盘事件"
            }
        }
    }

    static var accessibilityGranted: Bool {
        AXIsProcessTrusted() && CGPreflightPostEventAccess()
    }

    @discardableResult
    static func requestAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        _ = CGRequestPostEventAccess()
        return accessibilityGranted
    }

    func send(_ action: BridgeAction, phase: KeyPhase) throws {
        guard Self.accessibilityGranted else { throw RelayError.accessibilityDenied }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first else {
            throw RelayError.codexNotRunning
        }

        switch action {
        case .agent1: if phase == .down { try post(keyCode: 18, flags: .maskCommand, to: app) }
        case .agent2: if phase == .down { try post(keyCode: 19, flags: .maskCommand, to: app) }
        case .agent3: if phase == .down { try post(keyCode: 20, flags: .maskCommand, to: app) }
        case .agent4: if phase == .down { try post(keyCode: 21, flags: .maskCommand, to: app) }
        case .agent5: if phase == .down { try post(keyCode: 23, flags: .maskCommand, to: app) }
        case .agent6: if phase == .down { try post(keyCode: 22, flags: .maskCommand, to: app) }
        case .quickAction:
            if phase == .down { try post(keyCode: 3, flags: [.maskControl, .maskAlternate, .maskCommand], to: app) }
        case .approve:
            if phase == .down { try post(keyCode: 36, flags: [], to: app) }
        case .decline:
            if phase == .down { try post(keyCode: 53, flags: [], to: app) }
        case .newChat:
            if phase == .down { try post(keyCode: 45, flags: .maskCommand, to: app) }
        case .pushToTalk:
            // Codex advertises Control+Shift+D for dictation. Preserve the
            // physical F11 press duration so both a tap and a long press have
            // the same lifecycle as using Codex's native shortcut directly.
            let flags: CGEventFlags = [.maskControl, .maskShift]
            if phase == .down {
                try postTransition(keyCode: 2, flags: flags, keyDown: true, to: app) // D
            } else {
                try postTransition(keyCode: 2, flags: flags, keyDown: false, to: app)
            }
        case .send:
            if phase == .down { try post(keyCode: 36, flags: [.maskControl, .maskAlternate, .maskCommand], to: app) }
        case .historyBack:
            if phase == .down { try post(keyCode: 33, flags: [.maskControl, .maskAlternate, .maskCommand], to: app) }
        case .historyForward:
            if phase == .down { try post(keyCode: 30, flags: [.maskControl, .maskAlternate, .maskCommand], to: app) }
        case .confirm:
            if phase == .up || phase == .down { try post(keyCode: 46, flags: [.maskControl, .maskShift], to: app) }
        default:
            return
        }
    }

    private func post(keyCode: CGKeyCode, flags: CGEventFlags, to app: NSRunningApplication) throws {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw RelayError.eventCreationFailed
        }
        down.flags = flags
        up.flags = flags
        down.setIntegerValueField(.eventSourceUserData, value: Self.eventSourceTag)
        up.setIntegerValueField(.eventSourceUserData, value: Self.eventSourceTag)
        down.postToPid(app.processIdentifier)
        up.postToPid(app.processIdentifier)
    }

    private func postTransition(keyCode: CGKeyCode, flags: CGEventFlags, keyDown: Bool,
                                to app: NSRunningApplication) throws {
        guard let source = CGEventSource(stateID: .privateState),
              let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else {
            throw RelayError.eventCreationFailed
        }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: Self.eventSourceTag)
        event.postToPid(app.processIdentifier)
    }

}
