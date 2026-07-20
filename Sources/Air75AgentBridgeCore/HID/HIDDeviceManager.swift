import Combine
import CoreGraphics
import Foundation
import IOKit.hid
import IOKit.hidsystem

public final class HIDDeviceManager: ObservableObject, KeyboardDeviceProvider, KeyboardInputProvider, @unchecked Sendable {
    @Published public private(set) var devices: [DeviceSnapshot] = []
    @Published public private(set) var recentEvents: [HIDEvent] = []
    @Published public private(set) var isRunning = false
    @Published public private(set) var listenAccessGranted = false
    @Published public private(set) var managerOpenResult: IOReturn = kIOReturnNotOpen
    @Published public var calibrationMode = false

    public var eventHandler: (@Sendable (HIDEvent) -> Void)?
    /// Reports only which verified interface was active. It intentionally
    /// carries no usage or value, so ordinary typing remains private while a
    /// wireless lighting driver can still follow the active receiver.
    public var deviceActivityHandler: (@Sendable (HIDInterfaceSnapshot) -> Void)?
    public var configuration: BridgeConfiguration {
        didSet { refresh() }
    }

    private let manager: IOHIDManager
    private let profileRegistry: DeviceProfileRegistry
    private let lock = NSLock()
    private var recognizedDevicePointers = Set<UInt>()
    private var interfaceCache: [UInt: HIDInterfaceSnapshot] = [:]

    public init(configuration: BridgeConfiguration = BridgeConfiguration(), profile: DeviceProfile? = nil,
                registry: DeviceProfileRegistry? = nil) {
        self.configuration = configuration
        if let registry {
            profileRegistry = registry
        } else if let profile {
            profileRegistry = DeviceProfileRegistry(profiles: [profile])
        } else {
            profileRegistry = .loadBundled()
        }
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    deinit { stop() }

    public func start() {
        guard !isRunning else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerSetDeviceMatching(manager, nil)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.deviceMatched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.deviceRemoved, context)
        IOHIDManagerRegisterInputValueCallback(manager, Self.inputValueReceived, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        listenAccessGranted = Self.checkListenAccess()
        managerOpenResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        isRunning = true
        refresh()
    }

    public static func checkListenAccess() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
            && CGPreflightListenEventAccess()
    }

    @discardableResult
    public func requestListenAccess() -> Bool {
        let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        _ = CGRequestListenEventAccess()
        listenAccessGranted = granted || Self.checkListenAccess()
        restart()
        return listenAccessGranted
    }

    public func restart() {
        stop()
        start()
    }

    public func stop() {
        guard isRunning else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        isRunning = false
        lock.lock()
        recognizedDevicePointers.removeAll()
        interfaceCache.removeAll()
        lock.unlock()
    }

    public func refresh() {
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            DispatchQueue.main.async { self.devices = [] }
            return
        }
        let snapshots = set.compactMap(snapshot(for:))
        rebuildDevices(from: snapshots)
    }

    public func confirmBluetoothAssociation(_ device: DeviceSnapshot) -> DeviceFingerprint? {
        guard device.transports.contains(.bluetooth), let interface = device.interfaces.first else { return nil }
        return DeviceFingerprintMatcher.fingerprint(
            for: interface,
            confirmedBluetoothAlias: "\(interface.vendorID):\(interface.productID)"
        )
    }

    public func clearEvents() {
        DispatchQueue.main.async { self.recentEvents.removeAll() }
    }

    public static func enumerateAllInterfaces() -> [HIDInterfaceSnapshot] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        let instance = HIDDeviceManager(registry: .loadBundled())
        return set.compactMap(instance.snapshot(for:))
    }

    private func snapshot(for device: IOHIDDevice) -> HIDInterfaceSnapshot? {
        let vendorID = integerProperty(device, key: kIOHIDVendorIDKey) ?? 0
        let productID = integerProperty(device, key: kIOHIDProductIDKey) ?? 0
        let product = stringProperty(device, key: kIOHIDProductKey) ?? "Unknown HID Device"
        let manufacturer = stringProperty(device, key: kIOHIDManufacturerKey)
        let serial = stringProperty(device, key: kIOHIDSerialNumberKey)
        let transport = Self.transport(from: stringProperty(device, key: kIOHIDTransportKey))
        let usagePage = integerProperty(device, key: kIOHIDPrimaryUsagePageKey) ?? 0
        let usage = integerProperty(device, key: kIOHIDPrimaryUsageKey) ?? 0

        guard let match = profileRegistry.bestMatch(
            vendorID: vendorID,
            productID: productID,
            product: product,
            manufacturer: manufacturer,
            transport: transport,
            usagePage: usagePage,
            usage: usage,
            confirmedFingerprint: configuration.confirmedBluetoothFingerprint
        ) else { return nil }
        let confidence: Int
        let confirmation: Bool
        switch match.recognition {
        case .recognized(let value): confidence = value; confirmation = false
        case .bluetoothCandidate(let value): confidence = value; confirmation = true
        case .rejected: return nil
        }

        let pointer = Self.pointerID(device)
        let snapshot = HIDInterfaceSnapshot(
            id: String(format: "%016llx", registryID(for: device) ?? UInt64(pointer)),
            vendorID: vendorID,
            productID: productID,
            productName: product,
            manufacturer: manufacturer,
            serialNumber: serial,
            transport: transport,
            usagePage: usagePage,
            usage: usage,
            locationID: integerProperty(device, key: kIOHIDLocationIDKey),
            maxInputReportSize: integerProperty(device, key: kIOHIDMaxInputReportSizeKey),
            maxOutputReportSize: integerProperty(device, key: kIOHIDMaxOutputReportSizeKey),
            maxFeatureReportSize: integerProperty(device, key: kIOHIDMaxFeatureReportSizeKey),
            recognitionConfidence: confidence,
            requiresPairingConfirmation: confirmation,
            profileID: match.profile.profileID,
            modelName: match.profile.model
        )
        lock.lock()
        recognizedDevicePointers.insert(pointer)
        interfaceCache[pointer] = snapshot
        lock.unlock()
        return snapshot
    }

    private func rebuildDevices(from interfaces: [HIDInterfaceSnapshot]) {
        let groups = Dictionary(grouping: interfaces) { item -> String in
            let profileID = item.profileID ?? "unknown"
            if let serial = item.serialNumber, !serial.isEmpty { return "\(profileID):serial:\(serial)" }
            return "\(profileID):\(item.transport.rawValue):\(item.vendorID):\(item.productID):\(DeviceFingerprintMatcher.normalize(item.productName))"
        }
        let result = groups.values.compactMap { group -> DeviceSnapshot? in
            guard let primary = group.sorted(by: { $0.recognitionConfidence > $1.recognitionConfidence }).first else { return nil }
            let confirmedAlias = primary.transport == .bluetooth && !primary.requiresPairingConfirmation
                ? "\(primary.vendorID):\(primary.productID)" : nil
            return DeviceSnapshot(
                fingerprint: DeviceFingerprintMatcher.fingerprint(for: primary, confirmedBluetoothAlias: confirmedAlias),
                productName: primary.productName,
                manufacturer: primary.manufacturer,
                serialNumber: primary.serialNumber,
                transports: Set(group.map(\.transport)),
                interfaces: group.sorted { ($0.usagePage, $0.usage) < ($1.usagePage, $1.usage) },
                lastSeenAt: Date(),
                isRecognized: group.allSatisfy { !$0.requiresPairingConfirmation },
                needsBluetoothAssociation: group.contains { $0.requiresPairingConfirmation },
                profileID: primary.profileID,
                modelName: primary.modelName
            )
        }.sorted { $0.productName < $1.productName }
        DispatchQueue.main.async { self.devices = result }
    }

    private func receive(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        let pointer = Self.pointerID(device)
        lock.lock()
        let recognized = recognizedDevicePointers.contains(pointer)
        let interface = interfaceCache[pointer]
        lock.unlock()
        guard recognized, let interface else { return }

        DispatchQueue.main.async {
            self.deviceActivityHandler?(interface)
        }

        let page = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        let integer = IOHIDValueGetIntegerValue(value)
        guard shouldPublish(page: page, usage: usage, value: integer) else { return }
        let event = HIDEvent(
            deviceID: interface.id,
            transport: interface.transport,
            usagePage: page,
            usage: usage,
            value: integer,
            reportID: Int(IOHIDElementGetReportID(element))
        )
        DispatchQueue.main.async {
            self.recentEvents.insert(event, at: 0)
            if self.recentEvents.count > 120 { self.recentEvents.removeLast(self.recentEvents.count - 120) }
            self.eventHandler?(event)
        }
    }

    private func shouldPublish(page: Int, usage: Int, value: Int) -> Bool {
        if calibrationMode { return true }
        if configuration.keyBindings.contains(where: {
            $0.isSupportedInputSource && $0.usagePage == page && $0.usage == usage
        }) { return true }
        if page >= 0xFF00 { return true }
        // Board-profile knob: right/left/click emit Print Screen, Scroll Lock and Pause.
        if page == 0x07 && (0x46...0x48).contains(usage) { return true }
        if page == 0x0C && [0xE2, 0xE9, 0xEA, 0xCD].contains(usage) { return true }
        return false
    }

    private func integerProperty(_ device: IOHIDDevice, key: String) -> Int? {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
    }

    private func stringProperty(_ device: IOHIDDevice, key: String) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    private func registryID(for device: IOHIDDevice) -> UInt64? {
        var value: UInt64 = 0
        let service = IOHIDDeviceGetService(device)
        guard service != 0, IORegistryEntryGetRegistryEntryID(service, &value) == KERN_SUCCESS else { return nil }
        return value
    }

    private static func pointerID(_ device: IOHIDDevice) -> UInt {
        UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque())
    }

    private static func transport(from value: String?) -> ConnectionTransport {
        switch value?.lowercased() {
        case let text? where text.contains("bluetooth"): return .bluetooth
        case let text? where text.contains("usb"): return .usb
        default: return .unknown
        }
    }

    private static let deviceMatched: IOHIDDeviceCallback = { context, _, _, _ in
        guard let context else { return }
        Unmanaged<HIDDeviceManager>.fromOpaque(context).takeUnretainedValue().refresh()
    }

    private static let deviceRemoved: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        let manager = Unmanaged<HIDDeviceManager>.fromOpaque(context).takeUnretainedValue()
        let pointer = pointerID(device)
        manager.lock.lock()
        manager.recognizedDevicePointers.remove(pointer)
        manager.interfaceCache.removeValue(forKey: pointer)
        manager.lock.unlock()
        manager.refresh()
    }

    private static let inputValueReceived: IOHIDValueCallback = { context, _, _, value in
        guard let context else { return }
        Unmanaged<HIDDeviceManager>.fromOpaque(context).takeUnretainedValue().receive(value)
    }
}
