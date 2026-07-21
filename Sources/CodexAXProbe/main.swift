import AppKit
import ApplicationServices
import Air75AgentBridgeCore
import Foundation

func value(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
    return result as AnyObject?
}

func string(_ element: AXUIElement, _ attribute: String) -> String? {
    value(element, attribute) as? String
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func center(_ element: AXUIElement) -> CGPoint? {
    guard let positionValue = value(element, kAXPositionAttribute),
          let sizeValue = value(element, kAXSizeAttribute) else { return nil }
    var position = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
          AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
    return CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
}

func click(_ point: CGPoint) {
    let source = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
}

func key(_ code: CGKeyCode, pid: pid_t) {
    CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)?.postToPid(pid)
    CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)?.postToPid(pid)
}

func key(_ code: CGKeyCode, flags: CGEventFlags, pid: pid_t) {
    let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)
    down?.flags = flags
    down?.postToPid(pid)
    let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)
    up?.flags = flags
    up?.postToPid(pid)
}

guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first else {
    fputs("Codex is not running\n", stderr)
    exit(1)
}

print("trusted=\(AXIsProcessTrusted()) pid=\(app.processIdentifier)")
let root = AXUIElementCreateApplication(app.processIdentifier)

if CommandLine.arguments.contains("--confirmation-state") {
    func confirmationNode(_ element: AXUIElement) -> (String?, [AXUIElement]) {
        let names = [kAXRoleAttribute, kAXVisibleChildrenAttribute, kAXChildrenAttribute] as CFArray
        var result: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(
            element, names, AXCopyMultipleAttributeOptions(rawValue: 0), &result
        ) == .success, let values = result as? [Any], values.count == 3 else {
            return (string(element, kAXRoleAttribute), children(element))
        }
        let visible = values[1] as? [AXUIElement] ?? []
        let regular = values[2] as? [AXUIElement] ?? []
        return (values[0] as? String, visible.isEmpty ? regular : visible)
    }
    func confirmationButtonLabels(_ element: AXUIElement) -> [String] {
        let names = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute] as CFArray
        var result: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(
            element, names, AXCopyMultipleAttributeOptions(rawValue: 0), &result
        ) == .success, let values = result as? [Any] else { return [] }
        return values.compactMap { $0 as? String }.filter { !$0.isEmpty }
    }
    let focusedValue = value(root, kAXFocusedUIElementAttribute)
    let focusedElement: AXUIElement? = focusedValue.flatMap {
        CFGetTypeID($0) == AXUIElementGetTypeID()
            ? unsafeBitCast($0, to: AXUIElement.self) : nil
    }
    var stack: [AXUIElement] = [focusedElement ?? root]
    var inspected = Set<CFHashCode>()
    var buttonLabels: [String] = []
    var remaining = 120
    while let element = stack.popLast(), remaining > 0 {
        remaining -= 1
        guard inspected.insert(CFHash(element)).inserted else { continue }
        let node = confirmationNode(element)
        if node.0 == (kAXButtonRole as String) {
            let currentLabels = confirmationButtonLabels(element)
            buttonLabels.append(contentsOf: currentLabels)
            if CodexDesktopConfirmationState.focusedButtonLabelsIndicateConfirmation(currentLabels) {
                print("CONFIRMATION waiting=true nodes=\(120 - remaining)")
                exit(EXIT_SUCCESS)
            }
            if CodexDesktopConfirmationState.buttonLabelsRequireConfirmation(buttonLabels) {
                print("CONFIRMATION waiting=true nodes=\(120 - remaining)")
                exit(EXIT_SUCCESS)
            }
        }
        stack.append(contentsOf: node.1)
    }
    print("CONFIRMATION waiting=false nodes=\(120 - remaining)")
    exit(EXIT_SUCCESS)
}

var seen = Set<CFHashCode>()
var remaining = 1500
var modelPicker: AXUIElement?
var reasoningItem: AXUIElement?
var shortcutSearch: AXUIElement?
var keyboardShortcutsMenuItem: AXUIElement?
var shortcutSummaryTexts: [String] = []
var dictationButton: AXUIElement?

func walk(_ element: AXUIElement, depth: Int) {
    guard remaining > 0, depth <= 30 else { return }
    remaining -= 1
    let hash = CFHash(element)
    guard seen.insert(hash).inserted else { return }
    let role = string(element, kAXRoleAttribute) ?? "?"
    let title = string(element, kAXTitleAttribute) ?? ""
    let desc = string(element, kAXDescriptionAttribute) ?? ""
    let help = string(element, kAXHelpAttribute) ?? ""
    let identifier = string(element, "AXDOMIdentifier") ?? string(element, kAXIdentifierAttribute) ?? ""
    let textValue = (value(element, kAXValueAttribute) as? String) ?? ""
    let focused = (value(element, kAXFocusedAttribute) as? Bool) == true
    if role == (kAXPopUpButtonRole as String), !title.isEmpty,
       title.range(of: #"(低|中|高|极高|low|medium|high)"#, options: [.regularExpression, .caseInsensitive]) != nil {
        modelPicker = element
    }
    if role == (kAXMenuItemRole as String),
       desc.range(of: #"(推理强度|reasoning effort)"#, options: [.regularExpression, .caseInsensitive]) != nil {
        reasoningItem = element
    }
    if role == (kAXTextFieldRole as String), desc.localizedCaseInsensitiveContains("快捷键") || desc.localizedCaseInsensitiveContains("shortcut") {
        shortcutSearch = element
    }
    if role == (kAXMenuItemRole as String), title == "Keyboard Shortcuts" || title == "键盘快捷键" {
        keyboardShortcutsMenuItem = element
    }
    if role == (kAXStaticTextRole as String), !textValue.isEmpty {
        shortcutSummaryTexts.append(textValue)
    }
    if role == (kAXButtonRole as String), desc == "听写" || desc.localizedCaseInsensitiveContains("dictation") {
        dictationButton = element
    }
    if !title.isEmpty || !desc.isEmpty || !help.isEmpty || !identifier.isEmpty ||
        (role == (kAXStaticTextRole as String) && !textValue.isEmpty) ||
        [kAXButtonRole as String, kAXTextAreaRole as String, kAXTextFieldRole as String,
         kAXSliderRole as String, kAXPopUpButtonRole as String, kAXMenuButtonRole as String,
         "AXLink"].contains(role) {
        let indent = String(repeating: "  ", count: min(depth, 12))
        print("\(indent)\(role) focused=\(focused) title=\(title.debugDescription) desc=\(desc.debugDescription) help=\(help.debugDescription) id=\(identifier.debugDescription) value=\(textValue.prefix(160).debugDescription)")
    }
    for child in children(element) { walk(child, depth: depth + 1) }
}

walk(root, depth: 0)

if CommandLine.arguments.contains("--escape") {
    app.activate(options: [.activateIgnoringOtherApps])
    key(53, pid: app.processIdentifier)
    Thread.sleep(forTimeInterval: 0.5)
    print("SENT_ESCAPE")
}

if CommandLine.arguments.contains("--send-f2") {
    app.activate(options: [.activateIgnoringOtherApps])
    key(120, pid: app.processIdentifier)
    Thread.sleep(forTimeInterval: 0.7)
    seen.removeAll(); remaining = 2000
    print("SENT_F2")
    walk(root, depth: 0)
}

if CommandLine.arguments.contains("--send-f13") {
    app.activate(options: [.activateIgnoringOtherApps])
    key(105, pid: app.processIdentifier)
    Thread.sleep(forTimeInterval: 0.7)
    seen.removeAll(); remaining = 2000
    print("SENT_F13")
    walk(root, depth: 0)
}

if CommandLine.arguments.contains("--send-dictation") {
    app.activate(options: [.activateIgnoringOtherApps])
    key(2, flags: [.maskControl, .maskShift], pid: app.processIdentifier)
    Thread.sleep(forTimeInterval: 0.8)
    seen.removeAll(); remaining = 2000
    print("SENT_DICTATION_SHORTCUT")
    walk(root, depth: 0)
}

if CommandLine.arguments.contains("--press-dictation-button"), let dictationButton {
    _ = AXUIElementPerformAction(dictationButton, kAXPressAction as CFString)
    Thread.sleep(forTimeInterval: 0.8)
    seen.removeAll(); remaining = 2000
    print("PRESSED_DICTATION_BUTTON")
    walk(root, depth: 0)
}

if CommandLine.arguments.contains("--shortcut-summary") {
    let pattern = #"F(?:1|2|3|13|14|15|16|17|18|19|20|21|22|23|24)$|推理|听写|Dictation|Fast|快速|批准|拒绝|发送|新建任务|模型"#
    for item in Array(NSOrderedSet(array: shortcutSummaryTexts)) as? [String] ?? []
    where item.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
        print("SHORTCUT \(item)")
    }
}

if CommandLine.arguments.contains("--open-keyboard-shortcuts"), let keyboardShortcutsMenuItem {
    app.activate(options: [.activateIgnoringOtherApps])
    _ = AXUIElementPerformAction(keyboardShortcutsMenuItem, kAXPressAction as CFString)
    Thread.sleep(forTimeInterval: 0.8)
    seen.removeAll()
    remaining = 2500
    print("OPENED_KEYBOARD_SHORTCUTS")
    walk(root, depth: 0)
}

if CommandLine.arguments.contains("--open-model-picker"), let modelPicker {
    print("OPENING_MODEL_PICKER")
    _ = AXUIElementPerformAction(modelPicker, kAXPressAction as CFString)
    Thread.sleep(forTimeInterval: 0.6)
    seen.removeAll()
    remaining = 1500
    walk(root, depth: 0)
}

if CommandLine.arguments.contains("--open-reasoning") {
    if reasoningItem == nil, let modelPicker {
        _ = AXUIElementPerformAction(modelPicker, kAXPressAction as CFString)
        Thread.sleep(forTimeInterval: 0.35)
        seen.removeAll(); remaining = 1500
        walk(root, depth: 0)
    }
    if let reasoningItem {
        print("OPENING_REASONING")
        _ = AXUIElementPerformAction(reasoningItem, kAXPressAction as CFString)
        Thread.sleep(forTimeInterval: 0.5)
        seen.removeAll(); remaining = 1500
        walk(root, depth: 0)
    }
}

if CommandLine.arguments.contains("--enter-reasoning") {
    app.activate(options: [.activateIgnoringOtherApps])
    if reasoningItem == nil, let modelPicker {
        _ = AXUIElementPerformAction(modelPicker, kAXPressAction as CFString)
        Thread.sleep(forTimeInterval: 0.35)
        seen.removeAll(); remaining = 1500
        walk(root, depth: 0)
    }
    if let reasoningItem {
        _ = AXUIElementSetAttributeValue(reasoningItem, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true)?.postToPid(app.processIdentifier)
        CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: false)?.postToPid(app.processIdentifier)
        Thread.sleep(forTimeInterval: 0.6)
        print("ENTERED_REASONING")
        seen.removeAll(); remaining = 1500
        walk(root, depth: 0)
    }
}

if CommandLine.arguments.contains("--click-reasoning") {
    app.activate(options: [.activateIgnoringOtherApps])
    if reasoningItem == nil, let modelPicker {
        _ = AXUIElementPerformAction(modelPicker, kAXPressAction as CFString)
        Thread.sleep(forTimeInterval: 0.35)
        seen.removeAll(); remaining = 1500
        walk(root, depth: 0)
    }
    if let reasoningItem, let point = center(reasoningItem) {
        print("CLICKING_REASONING \(point)")
        click(point)
        Thread.sleep(forTimeInterval: 0.6)
        print("CLICKED_REASONING")
        seen.removeAll(); remaining = 1500
        walk(root, depth: 0)
    }
}

if CommandLine.arguments.contains("--picker-down") {
    print("PICKER_DOWN")
    key(125, pid: app.processIdentifier)
    Thread.sleep(forTimeInterval: 0.35)
    seen.removeAll(); remaining = 1500
    walk(root, depth: 0)
}

if CommandLine.arguments.contains("--picker-enter") {
    print("PICKER_ENTER")
    key(36, pid: app.processIdentifier)
    Thread.sleep(forTimeInterval: 0.45)
    seen.removeAll(); remaining = 1500
    walk(root, depth: 0)
}

if let search = CommandLine.arguments.first(where: { $0.hasPrefix("--search=") })?.dropFirst("--search=".count),
   let shortcutSearch {
    _ = AXUIElementSetAttributeValue(shortcutSearch, kAXValueAttribute as CFString, String(search) as CFString)
    Thread.sleep(forTimeInterval: 0.5)
    print("SEARCHED_REASONING")
    seen.removeAll(); remaining = 1500
    walk(root, depth: 0)
}
