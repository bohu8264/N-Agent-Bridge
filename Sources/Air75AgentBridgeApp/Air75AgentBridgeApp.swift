import Air75AgentBridgeCore
import AppKit
import SwiftUI

@main
struct Air75AgentBridgeApp: App {
    @StateObject private var store = BridgeStore()
    @AppStorage("interfaceLanguage") private var interfaceLanguageRawValue = InterfaceLanguage.systemDefault.rawValue

    private var interfaceLanguage: InterfaceLanguage {
        InterfaceLanguage(rawValue: interfaceLanguageRawValue) ?? .systemDefault
    }

    private var interfaceLanguageSelection: Binding<InterfaceLanguage> {
        Binding(
            get: { interfaceLanguage },
            set: { interfaceLanguageRawValue = $0.rawValue }
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environment(\.interfaceLanguage, interfaceLanguage)
                .environment(\.interfaceLanguageSelection, interfaceLanguageSelection)
                .environment(\.locale, interfaceLanguage.locale)
                .background(WindowPlacementGuard())
                .frame(minWidth: 860, minHeight: 620)
        }
        .defaultSize(width: 1180, height: 780)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("N Agent Bridge").font(.headline)
                        Text(store.currentDevice == nil
                             ? interfaceLanguage.text("等待键盘连接", "Waiting for keyboard")
                             : interfaceLanguage.text("已连接 · 可以使用", "Connected · Ready"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                Text(store.configuration.enabled
                     ? interfaceLanguage.text("Codex 控制已开启", "Codex control is on")
                     : interfaceLanguage.text("Codex 控制已停止", "Codex control is off"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(store.configuration.enabled
                       ? interfaceLanguage.text("停止并恢复键盘", "Stop and restore keyboard")
                       : interfaceLanguage.text("启用控制", "Enable control")) {
                    if store.configuration.enabled && !store.currentHardwareProfileNeedsInstallation {
                        store.disable()
                    } else {
                        store.oneClickEnable()
                    }
                }
                Divider()
                Button(interfaceLanguage.text("打开 N Agent Bridge", "Open N Agent Bridge")) { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first?.makeKeyAndOrderFront(nil) }
                Button(interfaceLanguage.text("退出", "Quit")) { NSApp.terminate(nil) }
            }.padding(10).frame(width: 240)
        } label: {
            Label("N Agent Bridge", systemImage: store.currentDevice == nil ? "keyboard.badge.ellipsis" : "keyboard.fill")
        }
    }
}

private struct WindowPlacementGuard: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowProbeView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowProbeView: NSView {
    private var hasAdjustedWindow = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !hasAdjustedWindow, let window else { return }
        hasAdjustedWindow = true
        DispatchQueue.main.async { [weak window] in
            guard let window,
                  let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame else { return }

            window.title = "N Agent Bridge"
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false

            var frame = window.frame
            let minimumWidth = min(860, visibleFrame.width)
            let minimumHeight = min(620, visibleFrame.height)
            frame.size.width = min(max(frame.width, minimumWidth), visibleFrame.width)
            frame.size.height = min(max(frame.height, minimumHeight), visibleFrame.height)
            frame.origin.x = min(max(frame.origin.x, visibleFrame.minX), visibleFrame.maxX - frame.width)
            frame.origin.y = min(max(frame.origin.y, visibleFrame.minY), visibleFrame.maxY - frame.height)
            window.minSize = NSSize(width: minimumWidth, height: minimumHeight)
            window.setFrame(frame, display: true)
        }
    }
}
