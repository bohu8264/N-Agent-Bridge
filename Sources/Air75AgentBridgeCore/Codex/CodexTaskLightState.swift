import Foundation

/// The five user-facing states supported by the Air75 V3 sidelight.
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

/// User-selectable colors for the single Codex status sidelight. Keeping the
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
    public var state: CodexTaskLightState
    public var eventDate: Date?

    public init(threadID: String?, state: CodexTaskLightState, eventDate: Date?) {
        self.threadID = threadID
        self.state = state
        self.eventDate = eventDate
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

    public static func parse(data: Data, now: Date = Date()) -> CodexTaskLightSnapshot {
        applyDecay(to: parseRaw(data: data), now: now)
    }

    /// Parses the rollout without the time-based complete/error decay so the
    /// result can be cached per file and re-decayed on every poll.
    public static func parseRaw(data: Data) -> CodexTaskLightSnapshot {
        var threadID: String?
        var state: CodexTaskLightState = .idle
        var eventDate: Date?

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

            let approvalMarker = [payloadType, status, name].joined(separator: "_")
            if approvalMarker.contains("approval")
                || approvalMarker.contains("request_user_input")
                || approvalMarker.contains("permission_request")
                || approvalMarker.contains("waiting_on_user_input") {
                state = .waitingForConfirmation
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

            // Once confirmation has been supplied, any resumed reasoning or
            // tool output means the task is actively running again.
            if state == .waitingForConfirmation && (
                payloadType == "agent_reasoning"
                    || payloadType == "agent_message"
                    || payloadType == "custom_tool_call_output"
                    || payloadType == "function_call_output"
                    || payloadType == "reasoning"
            ) {
                state = .reasoning
                eventDate = parseDate(timestampValue)
            }
        }

        return CodexTaskLightSnapshot(threadID: threadID, state: state, eventDate: eventDate)
    }

    /// Completed tasks stay green for 60 seconds and failed tasks stay red for
    /// 120 seconds, then both settle back to idle.
    public static func applyDecay(to snapshot: CodexTaskLightSnapshot, now: Date = Date()) -> CodexTaskLightSnapshot {
        var decayed = snapshot
        if decayed.state == .complete, let eventDate = decayed.eventDate,
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
