// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Air75AgentBridge",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Air75AgentBridge", targets: ["Air75AgentBridgeApp"]),
        .executable(name: "Air75HIDInspector", targets: ["Air75HIDInspector"]),
        .executable(name: "Air75ProtocolProbe", targets: ["Air75ProtocolProbe"]),
        .executable(name: "CodexAXProbe", targets: ["CodexAXProbe"]),
        .executable(name: "Air75CoreSelfTest", targets: ["Air75CoreSelfTest"]),
        .library(name: "Air75AgentBridgeCore", targets: ["Air75AgentBridgeCore"])
    ],
    targets: [
        .target(
            name: "Air75AgentBridgeCore",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "Air75AgentBridgeApp",
            dependencies: ["Air75AgentBridgeCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices")
            ]
        ),
        .executableTarget(
            name: "Air75HIDInspector",
            dependencies: ["Air75AgentBridgeCore"]
        ),
        .executableTarget(
            name: "Air75ProtocolProbe",
            dependencies: ["Air75AgentBridgeCore"],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "Air75CoreSelfTest",
            dependencies: ["Air75AgentBridgeCore"]
        ),
        .executableTarget(
            name: "CodexAXProbe",
            dependencies: ["Air75AgentBridgeCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices")
            ]
        ),
        .testTarget(
            name: "Air75AgentBridgeCoreTests",
            dependencies: ["Air75AgentBridgeCore"]
        )
    ]
)
