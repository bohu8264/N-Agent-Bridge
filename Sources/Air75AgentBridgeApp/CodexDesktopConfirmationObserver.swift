import Air75AgentBridgeCore
import AppKit
import ApplicationServices
import Foundation

/// Detects the currently visible Codex approval/elicitation card without
/// reading prompt or response text. Codex app-server is private to the Desktop
/// process, and MCP form elicitations are not persisted in rollout JSONL, so
/// Accessibility button semantics are the only local signal available today.
/// The visible task is correlated using Codex Desktop's structural activity
/// log (`conversationId` only).
final class CodexDesktopConfirmationObserver: @unchecked Sendable {
    struct Snapshot: Equatable, Sendable {
        var threadID: String?
        var isWaitingForConfirmation: Bool
    }

    var handler: ((Snapshot) -> Void)?

    private let bundleIdentifier = "com.openai.codex"
    private let queue = DispatchQueue(label: "Air75AgentBridge.CodexConfirmation", qos: .utility)
    private let lock = NSLock()
    private let activityReader: CodexDesktopActivityLogReader
    private var timer: DispatchSourceTimer?
    private var lastSnapshot: Snapshot?
    private var waiting = false
    private var nextFullScanAt = Date.distantPast

    init(logRoot: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/com.openai.codex", isDirectory: true)) {
        activityReader = CodexDesktopActivityLogReader(root: logRoot)
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: .milliseconds(750), leeway: .milliseconds(120))
        source.setEventHandler { [weak self] in self?.poll() }
        timer = source
        source.resume()
    }

    func stop() {
        lock.lock()
        let source = timer
        timer = nil
        lock.unlock()
        source?.cancel()
    }

    private func poll() {
        let now = Date()
        let fullScan = now >= nextFullScanAt
        if fullScan {
            nextFullScanAt = now.addingTimeInterval(waiting ? 5 : 30)
        }
        let detectedNow = Self.visibleConfirmationCard(in: bundleIdentifier, fullScan: fullScan)
        if fullScan {
            waiting = detectedNow
        } else if detectedNow {
            // A compact button group around the focused element is immediate
            // proof. A lightweight negative result is not enough to clear an
            // already visible card; the bounded full scan confirms removal
            // within five seconds.
            waiting = true
            nextFullScanAt = min(nextFullScanAt, now.addingTimeInterval(5))
        }
        let snapshot = Snapshot(
            threadID: waiting ? activityReader.currentActiveThreadID(now: now) : nil,
            isWaitingForConfirmation: waiting
        )
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        handler?(snapshot)
    }

    private static func visibleConfirmationCard(in bundleIdentifier: String, fullScan: Bool) -> Bool {
        guard AXIsProcessTrusted(),
              let application = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
              ).first(where: { !$0.isTerminated }) else { return false }

        let root = AXUIElementCreateApplication(application.processIdentifier)
        var stack: [AXUIElement]
        if fullScan {
            // Electron keeps hidden/off-screen windows and dismissed cards in
            // the app accessibility tree. Restrict full scans to the current
            // window so stale controls cannot create phantom orange lights.
            stack = [focusedWindow(of: root) ?? root]
        } else if let focused = focusedElement(of: root) {
            stack = [focused]
        } else {
            return false
        }
        var seen = Set<CFHashCode>()
        var remaining = fullScan ? 8_000 : 120

        // A LIFO traversal visits the newest/bottom-most conversation controls
        // before the long transcript in Electron's accessibility tree.
        while let element = stack.popLast(), remaining > 0 {
            remaining -= 1
            guard seen.insert(CFHash(element)).inserted else { continue }
            let node = nodeAttributes(of: element)
            let role = node.role
            if role == (kAXButtonRole as String) {
                let currentLabels = buttonLabels(of: element)
                if !fullScan,
                   CodexDesktopConfirmationState.focusedButtonLabelsIndicateConfirmation(currentLabels) {
                    return true
                }
                if CodexDesktopConfirmationState.buttonLabelsContainConfirmationAction(currentLabels),
                   localButtonGroupRequiresConfirmation(around: element) {
                    return true
                }
            }
            stack.append(contentsOf: node.children)
        }
        return false
    }

    /// Confirmation actions must belong to the same small Accessibility
    /// subtree. Never combine the composer's permanent "请求批准" button with
    /// an unrelated Cancel/Later button elsewhere in the Codex window.
    private static func localButtonGroupRequiresConfirmation(around button: AXUIElement) -> Bool {
        var element = button
        for _ in 0..<7 {
            guard let parent = parentElement(of: element) else { return false }
            let result = buttonLabels(in: parent, nodeLimit: 160)
            if CodexDesktopConfirmationState.buttonLabelsRequireConfirmation(result.labels) {
                return true
            }
            // Every higher ancestor contains at least this subtree. Once the
            // candidate is this large it is a page/window, not one card.
            if result.overflow { return false }
            element = parent
        }
        return false
    }

    private static func buttonLabels(
        in root: AXUIElement,
        nodeLimit: Int
    ) -> (labels: [String], overflow: Bool) {
        var stack = [root]
        var seen = Set<CFHashCode>()
        var labels: [String] = []
        var remaining = nodeLimit
        while let element = stack.popLast(), remaining > 0 {
            remaining -= 1
            guard seen.insert(CFHash(element)).inserted else { continue }
            let node = nodeAttributes(of: element)
            if node.role == (kAXButtonRole as String) {
                labels.append(contentsOf: buttonLabels(of: element))
            }
            stack.append(contentsOf: node.children)
        }
        return (labels, remaining == 0 && !stack.isEmpty)
    }

    private static func parentElement(of element: AXUIElement) -> AXUIElement? {
        guard let raw = attribute(kAXParentAttribute, of: element),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(raw, to: AXUIElement.self)
    }

    private static func focusedElement(of root: AXUIElement) -> AXUIElement? {
        guard let raw = attribute(kAXFocusedUIElementAttribute, of: root),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(raw, to: AXUIElement.self)
    }

    private static func focusedWindow(of root: AXUIElement) -> AXUIElement? {
        guard let raw = attribute(kAXFocusedWindowAttribute, of: root),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(raw, to: AXUIElement.self)
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as AnyObject?
    }

    private static func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        attribute(name, of: element) as? String
    }

    private static func nodeAttributes(of element: AXUIElement) -> (role: String?, children: [AXUIElement]) {
        let names = [kAXRoleAttribute, kAXVisibleChildrenAttribute, kAXChildrenAttribute] as CFArray
        var result: CFArray?
        let options = AXCopyMultipleAttributeOptions(rawValue: 0)
        guard AXUIElementCopyMultipleAttributeValues(element, names, options, &result) == .success,
              let values = result as? [Any], values.count == 3 else {
            return (
                stringAttribute(kAXRoleAttribute, of: element),
                attribute(kAXChildrenAttribute, of: element) as? [AXUIElement] ?? []
            )
        }
        let visible = values[1] as? [AXUIElement]
        let regular = values[2] as? [AXUIElement] ?? []
        // An explicitly empty AXVisibleChildren list means this subtree is
        // hidden. Fall back only when that attribute is unsupported.
        return (values[0] as? String, visible ?? regular)
    }

    private static func buttonLabels(of element: AXUIElement) -> [String] {
        let names = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute] as CFArray
        var result: CFArray?
        let options = AXCopyMultipleAttributeOptions(rawValue: 0)
        guard AXUIElementCopyMultipleAttributeValues(element, names, options, &result) == .success,
              let values = result as? [Any] else { return [] }
        return values.compactMap { $0 as? String }.filter { !$0.isEmpty }
    }
}

private final class CodexDesktopActivityLogReader {
    private let root: URL
    private var currentLogURL: URL?
    private var offset: UInt64 = 0
    private var partialLine = ""
    private var activeThreadID: String?
    private var nextDiscoveryAt = Date.distantPast

    init(root: URL) {
        self.root = root
    }

    func currentActiveThreadID(now: Date = Date()) -> String? {
        if currentLogURL == nil || now >= nextDiscoveryAt {
            nextDiscoveryAt = now.addingTimeInterval(15)
            if let newest = newestLog(), newest != currentLogURL {
                currentLogURL = newest
                offset = 0
                partialLine = ""
                activeThreadID = nil
            }
        }
        guard let url = currentLogURL,
              let handle = try? FileHandle(forReadingFrom: url) else { return activeThreadID }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return activeThreadID }
        if size < offset {
            offset = 0
            partialLine = ""
            activeThreadID = nil
        }
        if offset == 0, size > 8_000_000 {
            offset = size - 8_000_000
        }
        guard size > offset else { return activeThreadID }
        do {
            try handle.seek(toOffset: offset)
            let data = try handle.readToEnd() ?? Data()
            offset = size
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                return activeThreadID
            }
            let combined = partialLine + text
            if combined.hasSuffix("\n") {
                partialLine = ""
                activeThreadID = CodexDesktopConfirmationState.activeThreadID(
                    in: combined,
                    startingWith: activeThreadID
                )
            } else if let newline = combined.lastIndex(of: "\n") {
                let complete = String(combined[...newline])
                partialLine = String(combined[combined.index(after: newline)...])
                activeThreadID = CodexDesktopConfirmationState.activeThreadID(
                    in: complete,
                    startingWith: activeThreadID
                )
            } else {
                partialLine = combined
            }
        } catch {
            return activeThreadID
        }
        return activeThreadID
    }

    private func newestLog() -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return currentLogURL }
        var newest: (url: URL, date: Date)?
        for case let url as URL in enumerator where url.pathExtension == "log" {
            guard let values = try? url.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey]
            ), values.isRegularFile == true else { continue }
            let date = values.contentModificationDate ?? .distantPast
            if newest == nil || date > newest!.date { newest = (url, date) }
        }
        return newest?.url ?? currentLogURL
    }
}
