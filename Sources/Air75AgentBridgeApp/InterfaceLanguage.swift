import Foundation
import SwiftUI

enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .simplifiedChinese: return "中文"
        case .english: return "English"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    func text(_ chinese: String, _ english: String) -> String {
        self == .simplifiedChinese ? chinese : english
    }

    /// Translates short runtime messages emitted by hardware and permission
    /// workflows without changing their control flow or error handling.
    func runtimeText(_ source: String) -> String {
        guard self == .english else { return source }
        let exact = [
            "键盘控制已启用": "Keyboard control enabled",
            "专用按键现在只控制 Codex": "Dedicated keys now control Codex only",
            "需要 USB-C": "USB-C required",
            "首次写入键盘专用层时请连接数据线": "Connect a data cable for first-time keyboard setup",
            "还差系统权限": "System permissions required",
            "请分别允许输入监控和辅助功能": "Allow both Input Monitoring and Accessibility",
            "N Agent Bridge 已启用": "N Agent Bridge enabled",
            "请重启一次 Codex 后使用": "Restart Codex once before use",
            "专用按键 · 蓝牙可用": "Dedicated keys · Bluetooth ready",
            "启用失败": "Setup failed",
            "暂未停止": "Not stopped yet",
            "需要先恢复键盘原生 F 区，完成后才能安全拔线": "Restore the keyboard's native function keys before unplugging safely",
            "原始键位已恢复": "Original keymap restored",
            "键盘系统功能键与音量旋钮已还原": "System function keys and volume knob restored",
            "Codex 模式已开启": "Codex mode enabled",
            "Codex 模式已关闭": "Codex mode disabled",
            "按键已学习": "Key learned",
            "Codex 中继快捷键": "Codex relay shortcuts",
            "已就绪": "Ready",
            "Codex 尚未连接": "Codex is not connected",
            "请在首页点“一键启用”": "Use Enable on the Overview page",
            "需要输入监控": "Input Monitoring required",
            "允许 N Agent Bridge 后才能读取实体键": "Allow N Agent Bridge to read physical keys",
            "Codex 控制未授权": "Codex control not authorized",
            "等待批准": "Waiting for approval",
            "Agent 已完成": "Agent completed",
            "未分配": "Unassigned",
            "需要灯光通道": "Lighting channel required"
        ]
        if let translated = exact[source] { return translated }

        var result = source
        let replacements = [
            ("六个 Agent 状态已同步到各自实体键", "Six Agent states are synced to their physical keys"),
            ("普通侧灯灯效保持用户设置", "standard side-light effects keep your settings"),
            ("正在创建新任务", "Creating a new task"),
            ("请重启一次 Codex", "Restart Codex once"),
            ("正在思考 / 推理", "Thinking / Reasoning"),
            ("任务完成", "Task Complete"),
            ("需要确认", "Confirmation Required"),
            ("报错", "Error"),
            ("空闲", "Idle")
        ]
        for (chinese, english) in replacements {
            result = result.replacingOccurrences(of: chinese, with: english)
        }
        return result
    }

    static var systemDefault: InterfaceLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        return preferred.hasPrefix("zh") ? .simplifiedChinese : .english
    }

    static var saved: InterfaceLanguage {
        guard let raw = UserDefaults.standard.string(forKey: "interfaceLanguage") else {
            return .systemDefault
        }
        return InterfaceLanguage(rawValue: raw) ?? .systemDefault
    }
}

private struct InterfaceLanguageKey: EnvironmentKey {
    static let defaultValue = InterfaceLanguage.systemDefault
}

private struct InterfaceLanguageSelectionKey: EnvironmentKey {
    static let defaultValue: Binding<InterfaceLanguage> = .constant(.systemDefault)
}

extension EnvironmentValues {
    var interfaceLanguage: InterfaceLanguage {
        get { self[InterfaceLanguageKey.self] }
        set { self[InterfaceLanguageKey.self] = newValue }
    }

    var interfaceLanguageSelection: Binding<InterfaceLanguage> {
        get { self[InterfaceLanguageSelectionKey.self] }
        set { self[InterfaceLanguageSelectionKey.self] = newValue }
    }
}
