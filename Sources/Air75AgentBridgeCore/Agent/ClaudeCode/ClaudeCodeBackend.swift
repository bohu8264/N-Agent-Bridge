import Foundation

public final class ClaudeCodeBackend: AgentBackend, @unchecked Sendable {
    public let kind: BackendKind = .claudeCode
    public private(set) var connectionState: BackendConnectionState = .disconnected
    public var eventHandler: (@Sendable (BackendEvent) -> Void)?
    private let queue = DispatchQueue(label: "com.nagentbridge.claude")
    private var processes: [String: Process] = [:]

    public init() {}

    public func connect() {
        connectionState = ExecutableLocator.find("claude") == nil ? .unavailable : .connected
        if connectionState == .connected { eventHandler?(.connected) }
        else { eventHandler?(.failed(sessionID: nil, message: "未安装 Claude Code CLI")) }
    }

    public func disconnect() {
        queue.async {
            self.processes.values.forEach { $0.terminate() }
            self.processes.removeAll()
            self.connectionState = .disconnected
            self.eventHandler?(.disconnected(nil))
        }
    }

    public func createSession(projectPath: String, title: String?) {
        let id = UUID().uuidString
        eventHandler?(.sessionCreated(id: id, title: title))
    }

    public func send(prompt: String, sessionID: String?, projectPath: String, reasoning: ReasoningLevel, fastMode: Bool, planMode: Bool) {
        queue.async {
            guard let executable = ExecutableLocator.find("claude") else {
                self.eventHandler?(.failed(sessionID: sessionID, message: "未找到 Claude Code CLI")); return
            }
            let id = sessionID ?? UUID().uuidString
            let process = Process()
            let pipe = Pipe()
            process.executableURL = executable
            var arguments = ["-p", prompt, "--output-format", "stream-json", "--verbose", "--effort", reasoning.rawValue]
            if sessionID != nil { arguments += ["--resume", id] }
            if planMode { arguments += ["--permission-mode", "plan"] }
            process.arguments = arguments
            process.currentDirectoryURL = URL(fileURLWithPath: projectPath)
            process.standardOutput = pipe
            process.standardError = pipe
            self.processes[id] = process
            self.eventHandler?(.turnStarted(sessionID: id, turnID: id))
            self.eventHandler?(.state(sessionID: id, .running))
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                self?.eventHandler?(.output(sessionID: id, text: text))
            }
            process.terminationHandler = { [weak self] process in
                self?.queue.async {
                    self?.processes.removeValue(forKey: id)
                    if process.terminationStatus == 0 { self?.eventHandler?(.completed(sessionID: id)) }
                    else { self?.eventHandler?(.failed(sessionID: id, message: "Claude Code 退出码 \(process.terminationStatus)")) }
                }
            }
            do { try process.run() }
            catch { self.eventHandler?(.failed(sessionID: id, message: error.localizedDescription)) }
        }
    }

    public func stop(sessionID: String?) {
        guard let sessionID else { return }
        queue.async { self.processes[sessionID]?.interrupt() }
    }

    public func respondToApproval(id: String, approve: Bool) {
        eventHandler?(.failed(sessionID: nil, message: "Claude Code 的外部 permission callback 尚未连接；请求保持拒绝"))
    }
}
