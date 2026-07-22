import Foundation
import IOKit.hid

public enum Air75KeymapError: LocalizedError {
    case deviceNotFound
    case managerOpen(IOReturn)
    case writeFailed(IOReturn)
    case timeout(command: UInt8)
    case invalidResponse
    case invalidChecksum
    case invalidLength
    case incompatibleLayout(index: Int, value: UInt16)
    case verificationFailed
    case restoreFailed
    case originalBackupNotFound
    case encryptedSessionData
    case sessionKeyConflict(UInt8)

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "未找到 Air75 V3 的配置接口；请使用 USB-C 数据线连接，或插入 2.4G 接收器"
        case .managerOpen(let code):
            return "无法打开 Air75 V3 配置接口（0x\(String(UInt32(bitPattern: code), radix: 16))）"
        case .writeFailed(let code):
            return "Air75 V3 键位写入失败（0x\(String(UInt32(bitPattern: code), radix: 16))）"
        case .timeout(let command):
            return "等待 Air75 V3 键位响应超时（命令 0x\(String(command, radix: 16))）"
        case .invalidResponse:
            return "Air75 V3 返回了无效的键位协议帧"
        case .invalidChecksum:
            return "Air75 V3 键位协议校验失败"
        case .invalidLength:
            return "Air75 V3 键位表长度不符合 Air75 V3 ANSI 布局"
        case .incompatibleLayout(let index, let value):
            return "键盘第 \(index) 个矩阵位置不是已验证布局（0x\(String(value, radix: 16))），已停止写入"
        case .verificationFailed:
            return "键位写入后的逐字节回读校验失败，已尝试恢复原配置"
        case .restoreFailed:
            return "原始键位恢复后的逐字节校验失败"
        case .originalBackupNotFound:
            return "键盘里仍是 Codex 专用键位，但没有找到可验证的原始键位备份；为避免覆盖真实键位，已停止操作"
        case .encryptedSessionData:
            return "Air75 V3 返回的键位数据无法通过布局校验；请退出 NuPhyIO、重新插线后再试"
        case .sessionKeyConflict(let key):
            return "Air75 V3 会话密钥不一致（0x\(String(format: "%02X", key))）；请关闭其他键盘配置页面后重试"
        }
    }
}

public struct Air75KeymapInstallResult: Sendable {
    public var original: [UInt8]
    public var installed: [UInt8]
    public var changedChunkAddresses: [Int]
}

/// Safe, narrowly scoped Air75 V3 ANSI keymap writer. It backs up the full
/// 1568-byte map, changes only verified positions, and reads the whole map
/// back before reporting success.
public final class Air75V3KeymapController: @unchecked Sendable {
    public static let vendorID = 0x19F5
    public static let productID = 0x1028
    public static let dongleProductID = 0x2620
    public static let keymapByteCount = 1_568

    private static let getUseKeyMatrix: UInt8 = 0xB2
    private static let setUseKeyMatrix: UInt8 = 0xB3
    private static let chunkSize = 56
    private static let entriesPerLayer = 98
    private static let layerCount = 8

    public init() {}

    public static func hasBridgeProfile(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == keymapByteCount else { return false }
        for layer in [0, 4] {
            for physicalIndex in 1...12 {
                let entry = layer * entriesPerLayer + physicalIndex
                let offset = entry * 2
                let value = (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
                guard value == UInt16(0x67 + physicalIndex) else { return false }
            }
        }
        return true
    }

    /// Rejects encrypted or incompatible reads before they can be stored as
    /// an original backup. The pure transform validates every knob position.
    public static func isPlausibleKeymap(_ bytes: [UInt8]) -> Bool {
        (try? Air75V3KeymapController().makeBridgeProfile(from: bytes)) != nil
    }

    public func readKeymap() throws -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(Self.keymapByteCount)
        for address in stride(from: 0, to: Self.keymapByteCount, by: Self.chunkSize) {
            let length = min(Self.chunkSize, Self.keymapByteCount - address)
            let response = try KeymapProtocolSession(expectedCommand: Self.getUseKeyMatrix)
                .transact(
                    command: Self.getUseKeyMatrix,
                    length: UInt8(length),
                    address: UInt16(address),
                    handle: 0,
                    payload: []
                )
            result.append(contentsOf: response[8..<(8 + length)])
        }
        guard result.count == Self.keymapByteCount else { throw Air75KeymapError.invalidLength }
        return result
    }

    public func makeBridgeProfile(from original: [UInt8]) throws -> [UInt8] {
        guard original.count == Self.keymapByteCount else { throw Air75KeymapError.invalidLength }
        var profile = original

        // Verified Air75 V3 ANSI matrix positions. These dedicated events do
        // not also change system volume or display brightness on macOS.
        let knobEntries: [(index: Int, allowed: Set<UInt16>, replacement: UInt16)] = [
            (60, [0x00A8, 0x003B, 0x0048], 0x0048), // press -> Pause
            (96, [0x00AA, 0x003A, 0x0047], 0x0047), // left -> Scroll Lock
            (97, [0x00A9, 0x003C, 0x0046], 0x0046), // right -> Print Screen
        ]
        for layer in 0..<Self.layerCount {
            for item in knobEntries {
                let index = layer * Self.entriesPerLayer + item.index
                let current = keycode(in: profile, entry: index)
                // Air75 V3 1.0.16.6 can leave the eighth-layer knob press
                // unassigned. Accept that single verified factory variant,
                // then normalize it to the same dedicated Pause event used by
                // every other layer. Do not broaden the allowance to another
                // layer, matrix position, or unknown keycode.
                let isEighthLayerEmptyKnobPress = layer == 7
                    && item.index == 60
                    && current == 0x0000
                guard item.allowed.contains(current) || isEighthLayerEmptyKnobPress else {
                    throw Air75KeymapError.incompatibleLayout(index: index, value: current)
                }
                setKeycode(item.replacement, in: &profile, entry: index)
            }
        }

        for layer in [0, 4] {
            for physicalIndex in 1...12 {
                let entry = layer * Self.entriesPerLayer + physicalIndex
                setKeycode(UInt16(0x67 + physicalIndex), in: &profile, entry: entry)
            }
        }
        return profile
    }

    public func installBridgeProfile(expectedOriginal: [UInt8]? = nil) throws -> Air75KeymapInstallResult {
        let original = try readKeymap()
        if let expectedOriginal, original != expectedOriginal {
            throw Air75KeymapError.verificationFailed
        }
        let profile = try makeBridgeProfile(from: original)
        let changed = changedChunks(from: original, to: profile)
        guard !changed.isEmpty else {
            return Air75KeymapInstallResult(
                original: original,
                installed: profile,
                changedChunkAddresses: []
            )
        }

        do {
            try write(chunksAt: changed, from: profile)
            Thread.sleep(forTimeInterval: 0.25)
            guard try readKeymap() == profile else { throw Air75KeymapError.verificationFailed }
        } catch {
            try? write(chunksAt: changed, from: original)
            Thread.sleep(forTimeInterval: 0.25)
            guard (try? readKeymap()) == original else { throw Air75KeymapError.restoreFailed }
            throw error
        }
        return Air75KeymapInstallResult(
            original: original,
            installed: profile,
            changedChunkAddresses: changed
        )
    }

    @discardableResult
    public func restore(_ bytes: [UInt8]) throws -> [UInt8] {
        guard bytes.count == Self.keymapByteCount else { throw Air75KeymapError.invalidLength }
        let current = try readKeymap()
        let changed = changedChunks(from: current, to: bytes)
        try write(chunksAt: changed, from: bytes)
        Thread.sleep(forTimeInterval: 0.25)
        let readback = try readKeymap()
        guard readback == bytes else { throw Air75KeymapError.restoreFailed }
        return readback
    }

    private func changedChunks(from before: [UInt8], to after: [UInt8]) -> [Int] {
        stride(from: 0, to: Self.keymapByteCount, by: Self.chunkSize).filter { address in
            let end = min(address + Self.chunkSize, Self.keymapByteCount)
            return before[address..<end] != after[address..<end]
        }
    }

    private func write(chunksAt addresses: [Int], from bytes: [UInt8]) throws {
        for address in addresses {
            let end = min(address + Self.chunkSize, Self.keymapByteCount)
            let payload = Array(bytes[address..<end])
            _ = try KeymapProtocolSession(expectedCommand: Self.setUseKeyMatrix)
                .transact(
                    command: Self.setUseKeyMatrix,
                    length: UInt8(payload.count),
                    address: UInt16(address),
                    handle: 0,
                    payload: payload
                )
            Thread.sleep(forTimeInterval: 0.06)
        }
    }

    private func keycode(in bytes: [UInt8], entry: Int) -> UInt16 {
        let offset = entry * 2
        return (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    private func setKeycode(_ value: UInt16, in bytes: inout [UInt8], entry: Int) {
        let offset = entry * 2
        bytes[offset] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 1] = UInt8(value & 0xFF)
    }
}

private final class KeymapProtocolSession {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var awaitingCommand: UInt8
    private var response: [UInt8]?

    init(expectedCommand: UInt8) {
        awaitingCommand = expectedCommand
    }

    deinit { inputBuffer.deallocate() }

    func transact(
        command: UInt8,
        length: UInt8,
        address: UInt16,
        handle: UInt8,
        payload: [UInt8]
    ) throws -> [UInt8] {
        try NuPhyHIDOperationCoordinator.withExclusiveAccess {
            try transactLocked(
                command: command,
                length: length,
                address: address,
                handle: handle,
                payload: payload
            )
        }
    }

    private func transactLocked(
        command: UInt8,
        length: UInt8,
        address: UInt16,
        handle: UInt8,
        payload: [UInt8]
    ) throws -> [UInt8] {
        let productIDs = [
            Air75V3KeymapController.productID,
            Air75V3KeymapController.dongleProductID,
        ]
        let matches = productIDs.map { productID in
            [
                kIOHIDVendorIDKey: Air75V3KeymapController.vendorID,
                kIOHIDProductIDKey: productID,
                kIOHIDPrimaryUsagePageKey: 1,
                kIOHIDPrimaryUsageKey: 0,
            ]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetCurrent(),
            CFRunLoopMode.defaultMode.rawValue
        )
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else { throw Air75KeymapError.managerOpen(openResult) }
        defer {
            IOHIDManagerUnscheduleFromRunLoop(
                manager,
                CFRunLoopGetCurrent(),
                CFRunLoopMode.defaultMode.rawValue
            )
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        let ordered = devices.sorted { devicePriority($0) < devicePriority($1) }
        guard !ordered.isEmpty else { throw Air75KeymapError.deviceNotFound }

        var lastError: Error = Air75KeymapError.deviceNotFound
        for device in ordered {
            do {
                return try attempt(
                    on: device,
                    command: command,
                    length: length,
                    address: address,
                    handle: handle,
                    payload: payload
                )
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func attempt(
        on device: IOHIDDevice,
        command: UInt8,
        length: UInt8,
        address: UInt16,
        handle: UInt8,
        payload: [UInt8]
    ) throws -> [UInt8] {
        inputBuffer.initialize(repeating: 0, count: 64)
        IOHIDDeviceRegisterInputReportCallback(
            device,
            inputBuffer,
            64,
            Self.inputReport,
            Unmanaged.passUnretained(self).toOpaque()
        )
        let handshake = NuPhyS4ProtocolCodec.randomHandshake()
        let acknowledgement = try sendAndReceive(
            handshake.report,
            on: device,
            command: NuPhyS4ProtocolCodec.setSecretKeyCommand
        )
        do {
            try NuPhyS4ProtocolCodec.validateHandshakeAcknowledgement(acknowledgement)
        } catch NuPhyS4ProtocolCodec.DecodeError.invalidChecksum {
            throw Air75KeymapError.invalidChecksum
        } catch {
            throw Air75KeymapError.invalidResponse
        }

        let report = NuPhyS4ProtocolCodec.makeReport(
            command: command,
            length: length,
            address: address,
            handle: handle,
            payload: payload,
            sessionKey: handshake.sessionKey
        )
        let response = try sendAndReceive(report, on: device, command: command)
        do {
            return try NuPhyS4ProtocolCodec.decodeResponse(
                response,
                command: command,
                length: length,
                address: address,
                handle: handle,
                sessionKey: handshake.sessionKey
            )
        } catch NuPhyS4ProtocolCodec.DecodeError.invalidChecksum {
            throw Air75KeymapError.invalidChecksum
        } catch NuPhyS4ProtocolCodec.DecodeError.sessionKeyMismatch(let key) {
            throw Air75KeymapError.sessionKeyConflict(key)
        } catch {
            throw Air75KeymapError.invalidResponse
        }
    }

    private func sendAndReceive(
        _ reportBytes: [UInt8],
        on device: IOHIDDevice,
        command: UInt8
    ) throws -> [UInt8] {
        response = nil
        awaitingCommand = command
        var report = reportBytes
        let reportCount = report.count
        let writeResult = report.withUnsafeMutableBytes { raw in
            IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                0,
                raw.bindMemory(to: UInt8.self).baseAddress!,
                reportCount
            )
        }
        guard writeResult == kIOReturnSuccess else {
            throw Air75KeymapError.writeFailed(writeResult)
        }

        let deadline = Date().addingTimeInterval(1.5)
        while response == nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        guard let response else { throw Air75KeymapError.timeout(command: command) }
        return response
    }

    private func devicePriority(_ device: IOHIDDevice) -> Int {
        let productID = (IOHIDDeviceGetProperty(
            device,
            kIOHIDProductIDKey as CFString
        ) as? Int) ?? -1
        return productID == Air75V3KeymapController.productID ? 0 : 1
    }

    private static let inputReport: IOHIDReportCallback = { context, result, _, _, _, report, length in
        guard result == kIOReturnSuccess, let context, length == 64 else { return }
        let session = Unmanaged<KeymapProtocolSession>.fromOpaque(context).takeUnretainedValue()
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))
        guard bytes.count >= 2,
              bytes[0] == 0xAA,
              bytes[1] == session.awaitingCommand else { return }
        session.response = bytes
    }
}
