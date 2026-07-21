import Foundation

/// Small, text-free parsers used by the macOS app to correlate Codex's
/// currently visible task with a confirmation card. The activity log parser
/// reads only structural `active` and `conversationId` fields; the button
/// matcher receives Accessibility labels from buttons only, never chat text.
public enum CodexDesktopConfirmationState {
    public static func activeThreadID(in logText: String, startingWith initialID: String? = nil) -> String? {
        var activeThreadID = initialID
        for line in logText.split(whereSeparator: { $0.isNewline }) {
            guard line.contains("thread_stream_view_activity_changed"),
                  let threadID = field(named: "conversationId", in: line) else { continue }
            switch field(named: "active", in: line) {
            case "true":
                activeThreadID = threadID
            case "false" where activeThreadID == threadID:
                activeThreadID = nil
            default:
                break
            }
        }
        return activeThreadID
    }

    /// Confirmation surfaces always present at least one affirmative action
    /// and one way to decline/cancel. Requiring both groups prevents normal
    /// Codex navigation buttons from turning an Agent key orange.
    public static func buttonLabelsRequireConfirmation(_ labels: [String]) -> Bool {
        let normalized = confirmationActionLabels(labels)
        guard !normalized.isEmpty else { return false }
        let affirmativeMarkers = [
            "安装", "允许", "批准", "确认", "同意", "授权",
            "install", "allow", "approve", "confirm", "accept"
        ]
        let negativeMarkers = [
            "暂不", "拒绝", "取消", "不允许", "稍后",
            "notnow", "deny", "decline", "reject", "cancel", "later"
        ]
        let hasAffirmative = normalized.contains { label in
            affirmativeMarkers.contains { label.contains($0) }
        }
        let hasNegative = normalized.contains { label in
            negativeMarkers.contains { label.contains($0) }
        }
        return hasAffirmative && hasNegative
    }

    /// Returns whether one button exposes an actual confirmation action. The
    /// composer permanently shows a "请求批准 / Request approval" mode button;
    /// that button asks Codex to request approval later and is not itself a
    /// pending approval surface.
    public static func buttonLabelsContainConfirmationAction(_ labels: [String]) -> Bool {
        let normalized = confirmationActionLabels(labels)
        let markers = [
            "安装", "允许", "批准", "确认", "同意", "授权",
            "暂不", "拒绝", "取消", "不允许", "稍后",
            "install", "allow", "approve", "confirm", "accept",
            "notnow", "deny", "decline", "reject", "cancel", "later"
        ]
        return normalized.contains { label in
            markers.contains { label.contains($0) }
        }
    }

    /// A focused primary approval button is a sufficient fast-path signal.
    /// Deliberately excludes generic actions such as "继续" so normal Codex
    /// navigation and onboarding cannot be mistaken for a pending approval.
    public static func focusedButtonLabelsIndicateConfirmation(_ labels: [String]) -> Bool {
        let normalized = confirmationActionLabels(labels)
        let strongMarkers = [
            "安装", "允许", "批准", "拒绝", "暂不", "不允许", "授权",
            "install", "allow", "approve", "deny", "decline", "reject", "notnow"
        ]
        return normalized.contains { label in
            strongMarkers.contains { label.contains($0) }
        }
    }

    private static func confirmationActionLabels(_ labels: [String]) -> [String] {
        let normalized = labels.map(normalize)
        let passiveApprovalEntrypoints = [
            "请求批准", "请求审批", "requestapproval", "askforapproval"
        ]
        guard !normalized.contains(where: { label in
            passiveApprovalEntrypoints.contains { label.contains($0) }
        }) else { return [] }
        return normalized
    }

    private static func field(named name: String, in line: Substring) -> String? {
        guard let markerRange = line.range(of: "\(name)=") else { return nil }
        let suffix = line[markerRange.upperBound...]
        let value = suffix.prefix { !$0.isWhitespace }
        return value.isEmpty ? nil : String(value)
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
            .lowercased()
    }
}
