import Foundation

/// The five user-facing states shown on the six Agent indicator keys.
public enum CodexTaskLightState: String, Codable, CaseIterable, Sendable {
    case idle
    case reasoning
    case complete
    case waitingForConfirmation
    case error

    public var displayName: String {
        switch self {
        case .idle: return "空闲"
        case .reasoning: return "正在思考 / 推理"
        case .complete: return "任务完成"
        case .waitingForConfirmation: return "需要确认"
        case .error: return "报错"
        }
    }

    public var colorHex: String {
        switch self {
        case .idle: return "#FFFFFF"
        case .reasoning: return "#168BFF"
        case .complete: return "#30D158"
        case .waitingForConfirmation: return "#FF9F0A"
        case .error: return "#FF453A"
        }
    }
}

/// User-selectable colors for Codex Agent status indicators. Keeping the
/// palette in the persisted configuration means changing a color never changes
/// the task-state parser or the keyboard protocol bytes that are written.
public struct CodexTaskLightPalette: Codable, Equatable, Sendable {
    public var idle: String
    public var reasoning: String
    public var complete: String
    public var waitingForConfirmation: String
    public var error: String

    public init(
        idle: String = CodexTaskLightState.idle.colorHex,
        reasoning: String = CodexTaskLightState.reasoning.colorHex,
        complete: String = CodexTaskLightState.complete.colorHex,
        waitingForConfirmation: String = CodexTaskLightState.waitingForConfirmation.colorHex,
        error: String = CodexTaskLightState.error.colorHex
    ) {
        self.idle = idle
        self.reasoning = reasoning
        self.complete = complete
        self.waitingForConfirmation = waitingForConfirmation
        self.error = error
    }

    public static let `default` = CodexTaskLightPalette()

    public func colorHex(for state: CodexTaskLightState) -> String {
        switch state {
        case .idle: return idle
        case .reasoning: return reasoning
        case .complete: return complete
        case .waitingForConfirmation: return waitingForConfirmation
        case .error: return error
        }
    }

    public mutating func setColorHex(_ hex: String, for state: CodexTaskLightState) {
        switch state {
        case .idle: idle = hex
        case .reasoning: reasoning = hex
        case .complete: complete = hex
        case .waitingForConfirmation: waitingForConfirmation = hex
        case .error: error = hex
        }
    }
}

public struct CodexTaskLightSnapshot: Equatable, Sendable {
    public var threadID: String?
    public var title: String?
    public var projectPath: String?
    /// Stable Codex Desktop project identity from `thread-project-assignments`.
    /// This lets the custom-assignment UI mirror the sidebar hierarchy instead
    /// of guessing a project from a task's working directory.
    public var projectID: String?
    public var projectName: String?
    public var projectOrder: Int?
    public var state: CodexTaskLightState
    public var eventDate: Date?
    public var recencyAtMS: Int64
    public var isUnread: Bool
    /// Zero-based order from Codex Desktop's own `pinned-thread-ids` list.
    /// `nil` means the thread is not pinned in Codex.
    public var pinnedOrder: Int?

    public init(threadID: String?, title: String? = nil, projectPath: String? = nil,
                projectID: String? = nil, projectName: String? = nil, projectOrder: Int? = nil,
                state: CodexTaskLightState, eventDate: Date?, recencyAtMS: Int64 = 0,
                isUnread: Bool = false, pinnedOrder: Int? = nil) {
        self.threadID = threadID
        self.title = title
        self.projectPath = projectPath
        self.projectID = projectID
        self.projectName = projectName
        self.projectOrder = projectOrder
        self.state = state
        self.eventDate = eventDate
        self.recencyAtMS = recencyAtMS
        self.isUnread = isUnread
        self.pinnedOrder = pinnedOrder
    }

    public static let unassigned = CodexTaskLightSnapshot(
        threadID: nil, state: .idle, eventDate: nil
    )
}

/// Pure slot selection shared by the app and software-only self tests. Every
/// result contains exactly six entries so an empty custom key remains visibly
/// unassigned and its firmware light can be switched off.
public enum CodexAgentSlotResolver {
    public static let slotCount = 6

    public static func resolve(
        candidates: [CodexTaskLightSnapshot],
        mode: CodexAgentSourceMode,
        pinnedThreadIDs: [String?],
        customThreadIDs: [String?]
    ) -> [CodexTaskLightSnapshot] {
        let byID = Dictionary(uniqueKeysWithValues: candidates.compactMap { snapshot in
            snapshot.threadID.map { ($0, snapshot) }
        })
        let selected: [CodexTaskLightSnapshot]
        switch mode {
        case .recent:
            selected = Array(candidates.sorted(by: recencyOrder).prefix(slotCount))
        case .pinned:
            let officialPins = candidates
                .filter { $0.pinnedOrder != nil }
                .sorted { ($0.pinnedOrder ?? .max) < ($1.pinnedOrder ?? .max) }
            if officialPins.isEmpty {
                // Compatibility fallback for Codex builds that do not expose
                // `pinned-thread-ids` in local state yet.
                selected = pinnedThreadIDs.prefix(slotCount).map { id in
                    guard let id else { return .unassigned }
                    return byID[id] ?? CodexTaskLightSnapshot(threadID: id, state: .idle, eventDate: nil)
                }
            } else {
                selected = Array(officialPins.prefix(slotCount))
            }
        case .priority:
            selected = Array(candidates.sorted(by: priorityOrder).prefix(slotCount))
        case .custom:
            selected = Array(customThreadIDs.prefix(slotCount)).map { id in
                guard let id else { return .unassigned }
                return byID[id] ?? CodexTaskLightSnapshot(threadID: id, state: .idle, eventDate: nil)
            }
        }
        return Array(selected.prefix(slotCount))
            + Array(repeating: .unassigned, count: max(0, slotCount - selected.count))
    }

    private static func recencyOrder(_ lhs: CodexTaskLightSnapshot, _ rhs: CodexTaskLightSnapshot) -> Bool {
        if lhs.recencyAtMS != rhs.recencyAtMS { return lhs.recencyAtMS > rhs.recencyAtMS }
        return (lhs.threadID ?? "") < (rhs.threadID ?? "")
    }

    private static func priorityOrder(_ lhs: CodexTaskLightSnapshot, _ rhs: CodexTaskLightSnapshot) -> Bool {
        let left = priorityRank(lhs)
        let right = priorityRank(rhs)
        return left == right ? recencyOrder(lhs, rhs) : left < right
    }

    private static func priorityRank(_ snapshot: CodexTaskLightSnapshot) -> Int {
        if snapshot.state == .waitingForConfirmation || snapshot.state == .error { return 0 }
        if snapshot.isUnread { return 1 }
        if snapshot.state == .reasoning { return 2 }
        return 3
    }
}

/// Chooses the single sidelight color when several tasks are tracked at once.
/// There is only one physical sidelight, so it shows the state that most needs
/// the user's attention.
public enum CodexTaskLightAggregator {
    public static let priority: [CodexTaskLightState] = [
        .error, .waitingForConfirmation, .reasoning, .complete, .idle
    ]

    public static func aggregate(_ states: [CodexTaskLightState]) -> CodexTaskLightState {
        for candidate in priority where states.contains(candidate) { return candidate }
        return .idle
    }
}

/// Reads only event names and timestamps from a Codex rollout. Prompt and
/// response text is deliberately ignored.
public enum CodexRolloutStatusParser {
    public static let completionVisibleDuration: TimeInterval = 60
    public static let errorVisibleDuration: TimeInterval = 120
    /// A rollout can end without a terminal event after Codex or the Mac is
    /// force-quit. Treating that last reasoning/tool event as live forever is
    /// worse than allowing a very long quiet operation to refresh on its next
    /// event. Thirty minutes preserves long work while clearing abandoned runs.
    public static let reasoningStaleDuration: TimeInterval = 30 * 60

    public static func parse(data: Data, now: Date = Date()) -> CodexTaskLightSnapshot {
        applyDecay(to: parseRaw(data: data), now: now)
    }

    /// Parses the rollout without the time-based complete/error decay so the
    /// result can be cached per file and re-decayed on every poll.
    public static func parseRaw(data: Data) -> CodexTaskLightSnapshot {
        var threadID: String?
        var state: CodexTaskLightState = .idle
        var eventDate: Date?
        let activePayloadTypes: Set<String> = [
            "agent_reasoning", "agent_message", "reasoning",
            "custom_tool_call", "custom_tool_call_output",
            "function_call", "function_call_output",
            "mcp_tool_call", "mcp_tool_call_output",
            "web_search_call", "computer_tool_call",
            "patch_apply_begin", "patch_apply_end"
        ]

        for rawLine in data.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(rawLine)) as? [String: Any] else {
                continue
            }
            let envelopeType = (object["type"] as? String ?? "").lowercased()
            let payload = object["payload"] as? [String: Any] ?? [:]
            let payloadType = (payload["type"] as? String ?? "").lowercased()
            let status = (payload["status"] as? String ?? "").lowercased()
            let name = (payload["name"] as? String ?? "").lowercased()
            let timestampValue = object["timestamp"] as? String

            if envelopeType == "session_meta" {
                threadID = (payload["session_id"] as? String) ?? (payload["id"] as? String) ?? threadID
                continue
            }

            if payloadType == "task_started" || payloadType == "turn_started" {
                state = .reasoning
                eventDate = parseDate(timestampValue)
                continue
            }
            if payloadType == "task_complete" || payloadType == "turn_complete" {
                state = .complete
                eventDate = parseDate(timestampValue)
                continue
            }

            // Outputs and resolved approval events close an earlier request.
            // Some Codex builds repeat the original request_user_input name on
            // the output; checking its name first used to relight orange.
            let terminalApprovalStatuses: Set<String> = [
                "approved", "accepted", "completed", "resolved",
                "declined", "denied", "rejected", "cancelled", "canceled"
            ]
            let isToolOutput = payloadType.hasSuffix("_output")
            let isApprovalResolution = payloadType.contains("approval_response")
                || payloadType.contains("approval_result")
                || payloadType.contains("permission_response")
                || payloadType.contains("permission_result")
            if isToolOutput || isApprovalResolution {
                state = .reasoning
                eventDate = parseDate(timestampValue)
                continue
            }

            let isUserInputRequest = payloadType.contains("waiting_on_user_input")
                || (name.contains("request_user_input")
                    && (payloadType == "custom_tool_call"
                        || !terminalApprovalStatuses.contains(status)))
            let isApprovalRequest = payloadType.contains("request_approval")
                || payloadType.contains("requestapproval")
                || payloadType.contains("approval_request")
                || payloadType.contains("permission_request")
            if isUserInputRequest
                || (isApprovalRequest && !terminalApprovalStatuses.contains(status)) {
                state = .waitingForConfirmation
                eventDate = parseDate(timestampValue)
                continue
            }

            if (isApprovalRequest || name.contains("request_user_input")),
               terminalApprovalStatuses.contains(status) {
                state = .reasoning
                eventDate = parseDate(timestampValue)
                continue
            }

            // 用户主动停止（turn_aborted）不是故障，回到空闲而不是亮红灯。
            if envelopeType == "event_msg", payloadType == "turn_aborted" {
                state = .idle
                eventDate = parseDate(timestampValue)
                continue
            }

            let terminalError = envelopeType == "event_msg" && (
                payloadType == "error"
                    || payloadType == "task_failed"
                    || payloadType == "turn_failed"
                    || status == "failed"
                    || status == "denied"
            )
            if terminalError {
                state = .error
                eventDate = parseDate(timestampValue)
                continue
            }

            // Long-running rollouts can grow beyond the observer's bounded
            // tail window, which means the original turn_started event is no
            // longer present. Ongoing reasoning/tool activity is therefore a
            // positive running signal on its own, not only after approval.
            if activePayloadTypes.contains(payloadType) {
                state = .reasoning
                eventDate = parseDate(timestampValue)
            }
        }

        return CodexTaskLightSnapshot(threadID: threadID, state: state, eventDate: eventDate)
    }

    /// Completed tasks stay green for 60 seconds and failed tasks stay red for
    /// 120 seconds, then both settle back to idle.
    public static func applyDecay(
        to snapshot: CodexTaskLightSnapshot,
        now: Date = Date(),
        preserveUnreadCompletion: Bool = false
    ) -> CodexTaskLightSnapshot {
        var decayed = snapshot
        if decayed.state == .reasoning {
            guard let eventDate = decayed.eventDate,
                  now.timeIntervalSince(eventDate) <= reasoningStaleDuration else {
                decayed.state = .idle
                return decayed
            }
        } else if decayed.state == .complete, !preserveUnreadCompletion,
                  let eventDate = decayed.eventDate,
           now.timeIntervalSince(eventDate) > completionVisibleDuration {
            decayed.state = .idle
        } else if decayed.state == .error, let eventDate = decayed.eventDate,
                  now.timeIntervalSince(eventDate) > errorVisibleDuration {
            decayed.state = .idle
        }
        return decayed
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}
