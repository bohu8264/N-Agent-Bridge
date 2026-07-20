import Air75AgentBridgeCore
import Foundation

struct InspectorOutput: Codable {
    var capturedAt: Date
    var host: String
    var interfaces: [HIDInterfaceSnapshot]
}

let arguments = CommandLine.arguments
let listenIndex = arguments.firstIndex(of: "--listen")
let seconds = listenIndex.flatMap { index in
    arguments.indices.contains(index + 1) ? Double(arguments[index + 1]) : nil
} ?? 0

let interfaces = HIDDeviceManager.enumerateAllInterfaces()
let output = InspectorOutput(capturedAt: Date(), host: ProcessInfo.processInfo.hostName, interfaces: interfaces)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
encoder.dateEncodingStrategy = .iso8601
if let data = try? encoder.encode(output), let text = String(data: data, encoding: .utf8) {
    print(text)
}

if seconds > 0 {
    let manager = HIDDeviceManager()
    manager.calibrationMode = true
    manager.eventHandler = { event in
        guard let data = try? encoder.encode(event), let text = String(data: data, encoding: .utf8) else { return }
        print(text)
        fflush(stdout)
    }
    manager.start()
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    manager.stop()
}
