import Air75AgentBridgeCore
import AppKit
import Foundation

/// Keeps a read-only app-server connection for Codex's authoritative task
/// names. Codex's SQLite `threads.title` can remain the first message even
/// after the Desktop sidebar has generated or renamed a task. `thread/list`
/// exposes that final UI value as `Thread.name`.
///
/// Only `id` and `name` are forwarded. Prompt, response and preview fields are
/// discarded immediately and are never logged or persisted.
final class CodexDesktopTitleObserver: @unchecked Sendable {
    var handler: (([String: String]) -> Void)?

    private let queue = DispatchQueue(label: "NAgentBridge.CodexTitles", qos: .utility)
    private var process: Process?
    private var input: FileHandle?
    private var readBuffer = Data()
    private var timer: DispatchSourceTimer?
    private var nextRequestID = 1
    private var initializeRequestID: Int?
    private var listRequestID: Int?
    private var initialized = false
    private var retryAfter = Date.distantPast

    func start() {
        queue.async {
            guard self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: 2, leeway: .milliseconds(250))
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.async {
            self.timer?.cancel()
            self.timer = nil
            self.closeProcess()
        }
    }

    private func tick() {
        if process == nil {
            guard Date() >= retryAfter else { return }
            launch()
            return
        }
        guard initialized, listRequestID == nil else { return }
        requestTitles()
    }

    private func launch() {
        guard let executable = codexExecutableURL() else {
            retryAfter = Date().addingTimeInterval(10)
            return
        }
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { self?.consume(data) }
        }
        // Expected app-server warnings are intentionally discarded. They can
        // contain paths but are not useful to the product UI.
        stderr.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        process.terminationHandler = { [weak self] _ in
            self?.queue.async {
                self?.resetAfterTermination()
            }
        }
        do {
            try process.run()
            self.process = process
            input = stdin.fileHandleForWriting
            let requestID = sendRequest(method: "initialize", params: [
                "clientInfo": [
                    "name": "n_agent_bridge_title_index",
                    "title": "N Agent Bridge Title Index",
                    "version": "0.13.5"
                ]
            ])
            initializeRequestID = requestID
        } catch {
            closeProcess()
            retryAfter = Date().addingTimeInterval(10)
        }
    }

    private func requestTitles() {
        // `useStateDbOnly` is important while Codex Desktop owns an active
        // thread: it returns that live thread instead of omitting it during a
        // second process's rollout scan-and-repair pass.
        listRequestID = sendRequest(method: "thread/list", params: [
            "useStateDbOnly": true,
            "sourceKinds": [],
            "limit": 1_000,
            "sortKey": "recency_at",
            "sortDirection": "desc"
        ])
    }

    private func consume(_ data: Data) {
        readBuffer.append(data)
        while let newline = readBuffer.firstIndex(of: 0x0A) {
            let line = readBuffer[..<newline]
            readBuffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let message = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
            else { continue }
            handle(message)
        }
    }

    private func handle(_ message: [String: Any]) {
        guard let id = (message["id"] as? NSNumber)?.intValue
                ?? Int(message["id"] as? String ?? "") else { return }
        if id == initializeRequestID {
            initializeRequestID = nil
            guard message["error"] == nil else {
                closeProcess()
                retryAfter = Date().addingTimeInterval(10)
                return
            }
            sendNotification(method: "initialized", params: [:])
            initialized = true
            requestTitles()
            return
        }
        guard id == listRequestID else { return }
        listRequestID = nil
        guard message["error"] == nil else { return }
        let titles = CodexThreadListTitleIndex.titles(in: message)
        handler?(titles)
    }

    @discardableResult
    private func sendRequest(method: String, params: [String: Any]) -> Int {
        let id = nextRequestID
        nextRequestID += 1
        write(["id": id, "method": method, "params": params])
        return id
    }

    private func sendNotification(method: String, params: [String: Any]) {
        write(["method": method, "params": params])
    }

    private func write(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        try? input?.write(contentsOf: data)
    }

    private func resetAfterTermination() {
        process = nil
        input = nil
        readBuffer.removeAll(keepingCapacity: true)
        initializeRequestID = nil
        listRequestID = nil
        initialized = false
        retryAfter = Date().addingTimeInterval(5)
    }

    private func closeProcess() {
        let running = process
        process = nil
        input = nil
        readBuffer.removeAll(keepingCapacity: true)
        initializeRequestID = nil
        listRequestID = nil
        initialized = false
        if running?.isRunning == true { running?.terminate() }
    }

    private func codexExecutableURL() -> URL? {
        let fileManager = FileManager.default
        var candidates: [URL] = []
        if let bundleURL = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.openai.codex"
        ).first?.bundleURL {
            candidates.append(bundleURL.appendingPathComponent("Contents/Resources/codex"))
        }
        let home = fileManager.homeDirectoryForCurrentUser
        candidates.append(contentsOf: [
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
            URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"),
            home.appendingPathComponent("Applications/ChatGPT.app/Contents/Resources/codex"),
            home.appendingPathComponent("Applications/Codex.app/Contents/Resources/codex")
        ])
        if let cli = ExecutableLocator.find("codex") { candidates.append(cli) }
        return candidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) })
    }
}
