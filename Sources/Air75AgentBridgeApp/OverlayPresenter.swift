import Air75AgentBridgeCore
import AppKit
import SwiftUI

@MainActor
final class OverlayPresenter {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(title: String, detail: String, slots: [AgentSlot], selectedSlot: Int) {
        hideTask?.cancel()
        let view = BridgeOverlayView(title: title, detail: detail, slots: slots, selectedSlot: selectedSlot)
        let hosting = NSHostingView(rootView: view)
        let size = NSSize(width: 420, height: 126)
        let panel = self.panel ?? NSPanel(contentRect: NSRect(origin: .zero, size: size),
                                          styleMask: [.borderless, .nonactivatingPanel],
                                          backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.contentView = hosting
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - size.width / 2,
                                         y: screen.visibleFrame.maxY - size.height - 42))
        }
        panel.orderFrontRegardless()
        self.panel = panel
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { panel.orderOut(nil) }
        }
    }

    func hide() { hideTask?.cancel(); panel?.orderOut(nil) }
}

private struct BridgeOverlayView: View {
    let title: String
    let detail: String
    let slots: [AgentSlot]
    let selectedSlot: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text("AIR75 · CODEX").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                ForEach(slots) { slot in
                    HStack(spacing: 5) {
                        Circle().fill(Color(hex: slot.colorHex)).frame(width: 7, height: 7)
                        Text("\(slot.slotId)").font(.caption2.monospacedDigit())
                    }
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(slot.slotId == selectedSlot ? Color.white.opacity(0.13) : Color.clear, in: Capsule())
                }
            }
        }
        .padding(18)
        .frame(width: 420, height: 126)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.12)))
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) ?? 0x808080
        self.init(red: Double((value >> 16) & 0xff) / 255,
                  green: Double((value >> 8) & 0xff) / 255,
                  blue: Double(value & 0xff) / 255)
    }

    var rgbHex: String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let red = Int((max(0, min(1, color.redComponent)) * 255).rounded())
        let green = Int((max(0, min(1, color.greenComponent)) * 255).rounded())
        let blue = Int((max(0, min(1, color.blueComponent)) * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
