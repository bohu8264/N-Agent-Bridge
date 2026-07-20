import Foundation

public final class CodexAppServerBackend: AgentBackend, @unchecked Sendable {
    public let kind: BackendKind = .codex
    public private(set) var connectionState: BackendConnectionState = .disconnected
    public var eventHandler: (@Sendable (BackendEvent) -> Void)?

    public var executableURL: URL? { ExecutableLocator.find("codex") }
    public var isUsingExperimentalProtocol: Bool { true }

    private let queue = DispatchQueue(label: "com.nagentbridge.codex-app-server")
    private var process: Process?
    private var input: FileHandle?
    private var readBuffer = Data()
    private var nextID = 1
    private var pendingMethods: [Int: String] = [:]
    private var pendingTitles: [Int: String?] = [:]
    private var approvalRequestIDs: [String: Any] = [:]
    private var currentTurnIDs: [String: String] = [:]
    private var queuedTurn: (prompt: String, path: String, reasoning: ReasoningLevel, fast: Bool, plan: Bool)?

    public init() {}

    public func connect() {
        queue.async {
            guard self.process == nil else { return }
            guard let executable = self.executableURL else {
                self.setState(.unavailable)
                self.eventHandler?(.failed(sessionID: nil, message: "未找到 Codex CLI"))
                return
            }
            self.setState(.connecting)
            let process = Process()
            let stdout = Pipe()
            let stdin = Pipe()
            let stderr = Pipe()
            process.executableURL = executable
            process.arguments = ["app-server", "--stdio"]
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr
            process.terminationHandler = { [weak self] process in
                guard let self else { return }
                self.queue.async {
                    self.process = nil
                    self.input = nil
                    self.setState(process.terminationStatus == 0 ? .disconnected : .error)
                    self.eventHandler?(.disconnected("Codex app-server 已退出（\(process.terminationStatus)）"))
                }
            }
            stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                self?.queue.async { self?.consume(data) }
            }
            stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let message = String(data: data, encoding: .utf8) else { return }
                if message.localizedCaseInsensitiveContains("error") {
                    self?.eventHandler?(.failed(sessionID: nil, message: message.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
            do {
                try process.run()
                self.process = process
                self.input = stdin.fileHandleForWriting
                let id = self.sendRequest(method: "initialize", params: [
                    "clientInfo": ["name": "n-agent-bridge", "title": "N Agent Bridge", "version": "0.9.0"],
                    "capabilities": ["experimentalApi": true]
                ])
                self.pendingMethods[id] = "initialize"
            } catch {
                self.setState(.error)
                self.eventHandler?(.failed(sessionID: nil, message: error.localizedDescription))
            }
        }
    }

    public func disconnect() {
        queue.async {
            self.process?.terminate()
            self.process = nil
            self.input = nil
            self.setState(.disconnected)
        }
    }

    public func createSession(projectPath: String, title: String?) {
        queue.async {
            guard self.connectionState == .connected else {
                self.queuedTurn = nil
                self.connect()
                self.eventHandler?(.failed(sessionID: nil, message: "Codex 正在连接，请稍后重试"))
                return
            }
            let id = self.sendRequest(method: "thread/start", params: [
                "cwd": projectPath,
                "approvalPolicy": "on-request",
                "approvalsReviewer": "user",
                "sandbox": "workspace-write",
                "ephemeral": false,
                "serviceName": "N Agent Bridge"
            ])
            self.pendingMethods[id] = "thread/start"
            self.pendingTitles[id] = title
        }
    }

    public func send(prompt: String, sessionID: String?, projectPath: String, reasoning: ReasoningLevel, fastMode: Bool, planMode: Bool) {
        queue.async {
            guard let sessionID, !sessionID.isEmpty else {
                self.queuedTurn = (prompt, projectPath, reasoning, fastMode, planMode)
                self.createSession(projectPath: projectPath, title: nil)
                return
            }
            var params: [String: Any] = [
                "threadId": sessionID,
                "input": [["type": "text", "text": prompt]],
                "effort": reasoning.rawValue,
                "cwd": projectPath,
                "approvalPolicy": "on-request",
                "approvalsReviewer": "user",
                "serviceTier": fastMode ? "fast" : "default"
            ]
            if planMode {
                params["collaborationMode"] = ["mode": "plan", "settings": ["developer_instructions": NSNull()]]
            }
            let id = self.sendRequest(method: "turn/start", params: params)
            self.pendingMethods[id] = "turn/start:\(sessionID)"
            self.eventHandler?(.state(sessionID: sessionID, .thinking))
        }
    }

    public func stop(sessionID: String?) {
        queue.async {
            guard let sessionID, let turnID = self.currentTurnIDs[sessionID] else { return }
            let id = self.sendRequest(method: "turn/interrupt", params: ["threadId": sessionID, "turnId": turnID])
            self.pendingMethods[id] = "turn/interrupt:\(sessionID)"
        }
    }

    public func respondToApproval(id: String, approve: Bool) {
        queue.async {
            guard let rpcID = self.approvalRequestIDs.removeValue(forKey: id) else { return }
            self.sendResponse(id: rpcID, result: ["decision": approve ? "accept" : "decline"])
        }
    }

    private func consume(_ data: Data) {
        readBuffer.append(data)
        while let newline = readBuffer.firstIndex(of: 0x0A) {
            let line = readBuffer[..<newline]
            readBuffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            handle(object)
        }
    }

    private func handle(_ message: [String: Any]) {
        if let rawID = message["id"], let method = message["method"] as? String {
            handleServerRequest(id: rawID, method: method, params: message["params"] as? [String: Any] ?? [:])
            return
        }
        if let id = (message["id"] as? NSNumber)?.intValue ?? Int(message["id"] as? String ?? ""),
           let pending = pendingMethods.removeValue(forKey: id) {
            handleResponse(id: id, pending: pending, message: message)
            return
        }
        if let method = message["method"] as? String {
            handleNotification(method: method, params: message["params"] as? [String: Any] ?? [:])
        }
    }

    private func handleResponse(id: Int, pending: String, message: [String: Any]) {
        if let error = message["error"] as? [String: Any] {
            eventHandler?(.failed(sessionID: nil, message: error["message"] as? String ?? "Codex 协议错误"))
            return
        }
        let result = message["result"] as? [String: Any] ?? [:]
        if pending == "initialize" {
            sendNotification(method: "initialized", params: [:])
            setState(.connected)
            eventHandler?(.connected)
        } else if pending == "thread/start", let thread = result["thread"] as? [String: Any], let threadID = thread["id"] as? String {
            let title = pendingTitles.removeValue(forKey: id) ?? nil
            eventHandler?(.sessionCreated(id: threadID, title: title))
            if let queued = queuedTurn {
                queuedTurn = nil
                send(prompt: queued.prompt, sessionID: threadID, projectPath: queued.path,
                     reasoning: queued.reasoning, fastMode: queued.fast, planMode: queued.plan)
            }
        }
    }

    private func handleServerRequest(id: Any, method: String, params: [String: Any]) {
        guard ["item/commandExecution/requestApproval", "item/fileChange/requestApproval", "item/permissions/requestApproval"].contains(method) else {
            sendResponse(id: id, result: ["decision": "decline"])
            return
        }
        let localID = UUID().uuidString
        approvalRequestIDs[localID] = id
        let sessionID = params["threadId"] as? String ?? "unknown"
        let summary = (params["reason"] as? String)
            ?? (params["command"] as? String)
            ?? (params["itemId"] as? String).map { "Codex 请求批准操作 \($0)" }
            ?? "Codex 请求批准受保护操作"
        eventHandler?(.approval(sessionID: sessionID, ApprovalRequest(id: localID, method: method, summary: summary)))
    }

    private func handleNotification(method: String, params: [String: Any]) {
        let sessionID = params["threadId"] as? String ?? "unknown"
        switch method {
        case "turn/started":
            if let turn = params["turn"] as? [String: Any], let turnID = turn["id"] as? String {
                currentTurnIDs[sessionID] = turnID
                eventHandler?(.turnStarted(sessionID: sessionID, turnID: turnID))
                eventHandler?(.state(sessionID: sessionID, .running))
            }
        case "turn/completed":
            let turn = params["turn"] as? [String: Any]
            currentTurnIDs.removeValue(forKey: sessionID)
            let status = turn?["status"] as? String
            if status == "completed" { eventHandler?(.completed(sessionID: sessionID)) }
            else if status == "interrupted" { eventHandler?(.state(sessionID: sessionID, .stopped)) }
            else {
                let error = (turn?["error"] as? [String: Any])?["message"] as? String ?? "Codex 任务失败"
                eventHandler?(.failed(sessionID: sessionID, message: error))
            }
        case "item/agentMessage/delta":
            if let delta = params["delta"] as? String { eventHandler?(.output(sessionID: sessionID, text: delta)) }
        default:
            break
        }
    }

    @discardableResult
    private func sendRequest(method: String, params: [String: Any]) -> Int {
        let id = nextID
        nextID += 1
        write(["id": id, "method": method, "params": params])
        return id
    }

    private func sendNotification(method: String, params: [String: Any]) {
        write(["method": method, "params": params])
    }

    private func sendResponse(id: Any, result: [String: Any]) {
        write(["id": id, "result": result])
    }

    private func write(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        try? input?.write(contentsOf: data)
    }

    private func setState(_ value: BackendConnectionState) {
        connectionState = value
    }
}

public enum ExecutableLocator {
    public static func find(_ name: String) -> URL? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".local/bin/\(name)"),
            URL(fileURLWithPath: "/opt/homebrew/bin/\(name)"),
            URL(fileURLWithPath: "/usr/local/bin/\(name)"),
            URL(fileURLWithPath: "/usr/bin/\(name)")
        ]
        if let match = candidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) { return match }
        for component in ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":") ?? [] {
            let url = URL(fileURLWithPath: String(component)).appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }
}
