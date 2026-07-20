import Foundation

public protocol KeyboardDeviceProvider: AnyObject {
    var devices: [DeviceSnapshot] { get }
    func start()
    func stop()
    func refresh()
}

public protocol KeyboardInputProvider: AnyObject {
    var eventHandler: (@Sendable (HIDEvent) -> Void)? { get set }
}

public protocol KeyboardConfigurationProvider: AnyObject {
    func readCurrentProfile(for device: DeviceSnapshot) async throws -> Data
    func writeProfile(_ data: Data, to device: DeviceSnapshot) async throws
}

public protocol KeyboardLightingProvider: AnyObject {
    func capabilities(for device: DeviceSnapshot) async -> LightingCapabilities
    func restoreUserLighting() async throws
}

public protocol AgentBackend: AnyObject {
    var kind: BackendKind { get }
    var connectionState: BackendConnectionState { get }
    var eventHandler: (@Sendable (BackendEvent) -> Void)? { get set }
    func connect()
    func disconnect()
    func createSession(projectPath: String, title: String?)
    func send(prompt: String, sessionID: String?, projectPath: String, reasoning: ReasoningLevel, fastMode: Bool, planMode: Bool)
    func stop(sessionID: String?)
    func respondToApproval(id: String, approve: Bool)
}

public enum BackendEvent: Sendable {
    case connected
    case disconnected(String?)
    case sessionCreated(id: String, title: String?)
    case turnStarted(sessionID: String, turnID: String)
    case state(sessionID: String, AgentState)
    case approval(sessionID: String, ApprovalRequest)
    case output(sessionID: String, text: String)
    case completed(sessionID: String)
    case failed(sessionID: String?, message: String)
}
