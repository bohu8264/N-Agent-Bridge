import Foundation

public final class MappingEngine: @unchecked Sendable {
    public var actionHandler: (@Sendable (BridgeAction, HIDEvent, KeyPhase) -> Void)?
    public var configuration: BridgeConfiguration
    private let lock = NSLock()
    private var downAt: [String: Date] = [:]
    private var lastReleaseAt: [String: Date] = [:]

    public init(configuration: BridgeConfiguration) {
        self.configuration = configuration
    }

    public func handle(_ event: HIDEvent) {
        guard configuration.enabled, configuration.codexModeEnabled else { return }
        let key = "\(event.deviceID):\(event.usagePage):\(event.usage)"
        let binding = configuration.keyBindings.first {
            $0.isSupportedInputSource
                && $0.usagePage == event.usagePage
                && $0.usage == event.usage
        }

        if let binding {
            if event.value != 0 {
                lock.lock()
                let isAlreadyDown = downAt[key] != nil
                if !isAlreadyDown { downAt[key] = event.timestamp }
                lock.unlock()
                guard !isAlreadyDown else { return }
                actionHandler?(binding.action, event, .down)
            } else {
                lock.lock()
                let start = downAt.removeValue(forKey: key)
                let previous = lastReleaseAt[key]
                lastReleaseAt[key] = event.timestamp
                lock.unlock()
                let duration = start.map { event.timestamp.timeIntervalSince($0) } ?? 0
                let isDouble = previous.map { event.timestamp.timeIntervalSince($0) < 0.35 } ?? false
                actionHandler?(binding.action, event, duration >= 0.65 ? .longPress : (isDouble ? .doublePress : .up))
            }
            return
        }

        if event.usagePage == 0x07 {
            // Hardware profile uses Scroll Lock / Print Screen / Pause for the
            // knob so it cannot change macOS volume or brightness.
            if event.usage == 0x47, event.value != 0 { actionHandler?(.historyBack, event, .down) }
            if event.usage == 0x46, event.value != 0 { actionHandler?(.historyForward, event, .down) }
            if event.usage == 0x48 {
                if event.value != 0 {
                    lock.lock(); downAt[key] = event.timestamp; lock.unlock()
                } else {
                    lock.lock(); let start = downAt.removeValue(forKey: key); lock.unlock()
                    let duration = start.map { event.timestamp.timeIntervalSince($0) } ?? 0
                    actionHandler?(duration >= 0.65 ? .quickAction : .confirm, event,
                                   duration >= 0.65 ? .longPress : .up)
                }
            }
            return
        }

        guard event.value != 0, event.usagePage == 0x0C else { return }
        if event.usage == 0xE9 { actionHandler?(.historyForward, event, .down) }
        if event.usage == 0xEA { actionHandler?(.historyBack, event, .down) }
        if event.usage == 0xCD || event.usage == 0xE2 { actionHandler?(.confirm, event, .down) }
    }
}

public enum KeyPhase: String, Sendable {
    case down, up, doublePress, longPress
}
