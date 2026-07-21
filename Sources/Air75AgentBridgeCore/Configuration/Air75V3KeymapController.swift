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
    case sessionKeyConflict(UInt8)
    case encryptedSessionData

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound: return "未找到 Air75 V3 的配置接口；请使用 USB-C 数据线连接，或插入 2.4G 接收器"
        case .managerOpen(let code): return "无法打开 Air75 V3 配置接口（0x\(String(UInt32(bitPattern: code), radix: 16))）"
        case .writeFailed(let code): return "Air75 V3 键位写入失败（0x\(String(UInt32(bitPattern: code), radix: 16))）"
        case .timeout(let command): return "等待 Air75 V3 键位响应超时（命令 0x\(String(command, radix: 16))）"
        case .invalidResponse: return "Air75 V3 返回了无效的键位协议帧"
        case .invalidChecksum: return "Air75 V3 键位协议校验失败"
        case .invalidLength: return "Air75 V3 键位表长度不符合 Air75 V3 ANSI 布局"
        case .incompatibleLayout(let index, let value):
            return "键盘第 \(index) 个矩阵位置不是已验证布局（0x\(String(value, radix: 16))），已停止写入"
        case .verificationFailed: return "键位写入后的逐字节回读校验失败，已尝试恢复原配置"
        case .restoreFailed: return "原始键位恢复后的逐字节校验失败"
        case .originalBackupNotFound: return "键盘里仍是 Codex 专用键位，但没有找到可验证的原始键位备份；为避免覆盖真实键位，已停止操作"
        case .sessionKeyConflict(let key):
            return "键盘正处于另一个配置器的加密会话（会话密钥 0x\(String(format: "%02X", key))）。请关闭 NuPhyIO 等配置页面，然后重新插拔键盘"
        case .encryptedSessionData:
            return "键盘返回了加密会话数据；请完全退出 NuPhyIO，拔线并关闭键盘电源 10 秒后重新连接"
        }
    }
}

public struct Air75KeymapInstallResult: Sendable {
    public var original: [UInt8]
    public var installed: [UInt8]
    public var changedChunkAddresses: [Int]
}

public struct NuPhyS4KeymapGeometry: Codable, Equatable, Sendable {
    public var currentMode: Int
    public var layerCount: Int
    public var layersPerMode: Int
    public var rows: Int
    public var columns: Int
    public var extraKeyCount: Int

    public var entriesPerLayer: Int { rows * columns + extraKeyCount }
    public var bytesPerLayer: Int { entriesPerLayer * 2 }
    public var totalByteCount: Int { bytesPerLayer * layerCount }
}

public struct NuPhyS4ReadOnlyKeymapSnapshot: Sendable {
    public var geometry: NuPhyS4KeymapGeometry
    public var bytes: [UInt8]

    public func keycode(layer: Int, entry: Int) -> UInt16? {
        guard (0..<geometry.layerCount).contains(layer),
              (0..<geometry.entriesPerLayer).contains(entry) else { return nil }
        let offset = layer * geometry.bytesPerLayer + entry * 2
        guard bytes.indices.contains(offset + 1) else { return nil }
        return (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }
}

/// S4 geometry and keymap discovery shared by future NuPhy profiles. This
/// inspector sends only GetBase (0xA0) and GetUseKeys (0xB2); it exposes no
/// write method and therefore cannot alter firmware state.
public final class NuPhyS4ReadOnlyKeymapInspector: @unchecked Sendable {
    private let productID: Int

    public init(productID: Int) { self.productID = productID }

    public func readSnapshot() throws -> NuPhyS4ReadOnlyKeymapSnapshot {
        let base = try KeymapProtocolSession(
            expectedCommand: 0xA0,
            productIDs: [productID]
        ).transact(command: 0xA0, length: 8, address: 0, handle: 0, payload: [])
        guard base.count >= 16, base[4] >= 8 else { throw Air75KeymapError.invalidResponse }
        let payload = Array(base[8..<16])
        let extra = payload[5] & 0x80 != 0 ? Int(payload[5] & 0x7F) : 2
        let geometry = NuPhyS4KeymapGeometry(
            currentMode: Int(payload[0]),
            layerCount: Int(payload[1]),
            layersPerMode: Int(payload[2]),
            rows: Int(payload[3]),
            columns: Int(payload[4]),
            extraKeyCount: extra
        )
        guard (1...16).contains(geometry.layerCount),
              (1...8).contains(geometry.layersPerMode),
              (1...16).contains(geometry.rows),
              (1...24).contains(geometry.columns),
              (0...16).contains(geometry.extraKeyCount),
              geometry.totalByteCount > 0,
              geometry.totalByteCount <= Int(UInt16.max) else {
            throw Air75KeymapError.invalidLength
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(geometry.totalByteCount)
        for address in stride(from: 0, to: geometry.totalByteCount, by: 56) {
            let length = min(56, geometry.totalByteCount - address)
            let response = try KeymapProtocolSession(
                expectedCommand: Air75V3KeymapController.getUseKeyMatrix,
                productIDs: [productID]
            ).transact(
                command: Air75V3KeymapController.getUseKeyMatrix,
                length: UInt8(length),
                address: UInt16(address),
                handle: 0,
                payload: []
            )
            bytes.append(contentsOf: response[8..<(8 + length)])
        }
        guard bytes.count == geometry.totalByteCount else { throw Air75KeymapError.invalidLength }
        return NuPhyS4ReadOnlyKeymapSnapshot(geometry: geometry, bytes: bytes)
    }
}

/// Safe, narrowly-scoped Air75 V3 ANSI keymap writer based on the protocol used
/// by the official NuPhyIO configurator. It backs up the full 1568-byte map,
/// changes only verified matrix positions, then reads the entire map back.
public final class Air75V3KeymapController: @unchecked Sendable {
    public static let vendorID = 0x19F5
    public static let productID = 0x1028
    /// NuPhy U1 dongle：NuPhyIO 通过它以同一 S4 协议无线配置键盘。
    public static let dongleProductID = 0x2620
    public static let keymapByteCount = 1_568

    fileprivate static let getUseKeyMatrix: UInt8 = 0xB2
    private static let setUseKeyMatrix: UInt8 = 0xB3
    private static let chunkSize = 56
    private static let entriesPerLayer = 98
    private static let layerCount = 8

    public init() {}

    /// Detects backups that already contain the dedicated F13-F24 board row.
    /// Such a file is a Bridge profile, not a safe candidate for "restore
    /// original keyboard".
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

    /// Rejects encrypted/session-garbled reads before they can be persisted as
    /// an "original" backup. The pure profile transform already validates all
    /// verified knob matrix positions across every layer, so it is also the
    /// narrowest layout plausibility check available for this keyboard.
    public static func isPlausibleKeymap(_ bytes: [UInt8]) -> Bool {
        (try? Air75V3KeymapController().makeBridgeProfile(from: bytes)) != nil
    }

    public func readKeymap() throws -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(Self.keymapByteCount)
        for address in stride(from: 0, to: Self.keymapByteCount, by: Self.chunkSize) {
            let length = min(Self.chunkSize, Self.keymapByteCount - address)
            let response = try KeymapProtocolSession(expectedCommand: Self.getUseKeyMatrix)
                .transact(command: Self.getUseKeyMatrix, length: UInt8(length),
                          address: UInt16(address), handle: 0, payload: [])
            result.append(contentsOf: response[8..<(8 + length)])
        }
        guard result.count == Self.keymapByteCount else { throw Air75KeymapError.invalidLength }
        return result
    }

    public func makeBridgeProfile(from original: [UInt8]) throws -> [UInt8] {
        guard original.count == Self.keymapByteCount else { throw Air75KeymapError.invalidLength }
        var profile = original

        // Verified Air75 V3 ANSI matrix positions. Print Screen, Scroll Lock
        // and Pause are distinct HID events with no volume/brightness effect on
        // macOS. The previous 0.4.0 F1/F2/F3 values remain accepted for migration.
        let knobEntries: [(index: Int, allowed: Set<UInt16>, replacement: UInt16)] = [
            (60, [0x00A8, 0x003B, 0x0048], 0x0048), // press -> Pause
            (96, [0x00AA, 0x003A, 0x0047], 0x0047), // counter-clockwise -> Scroll Lock
            (97, [0x00A9, 0x003C, 0x0046], 0x0046), // clockwise -> Print Screen
        ]
        for layer in 0..<Self.layerCount {
            for item in knobEntries {
                let index = layer * Self.entriesPerLayer + item.index
                let current = keycode(in: profile, entry: index)
                guard item.allowed.contains(current) else {
                    throw Air75KeymapError.incompatibleLayout(index: index, value: current)
                }
                setKeycode(item.replacement, in: &profile, entry: index)
            }
        }

        // Mac base (layer 0) and Windows base (layer 4): physical F1-F12 emit
        // F13-F24. The app's session event tap consumes their macOS events
        // while Codex mode is active; the usages continue over Bluetooth.
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
            return Air75KeymapInstallResult(original: original, installed: profile, changedChunkAddresses: [])
        }

        do {
            try write(chunksAt: changed, from: profile)
            Thread.sleep(forTimeInterval: 0.25)
            guard try readKeymap() == profile else { throw Air75KeymapError.verificationFailed }
        } catch {
            // Only the chunks touched above are restored; all other user layers
            // remain byte-for-byte untouched throughout the transaction.
            try? write(chunksAt: changed, from: original)
            Thread.sleep(forTimeInterval: 0.25)
            guard (try? readKeymap()) == original else { throw Air75KeymapError.restoreFailed }
            throw error
        }
        return Air75KeymapInstallResult(original: original, installed: profile,
                                        changedChunkAddresses: changed)
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
                .transact(command: Self.setUseKeyMatrix, length: UInt8(payload.count),
                          address: UInt16(address), handle: 0, payload: payload)
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

/// Verified Kick75 ANSI/IO keymap writer. Kick75 has a 6x15 matrix plus two
/// encoder entries (92 entries per layer), so none of the Air75 V3 offsets are
/// reused. The original values below come from the attached 0x19F5:0x1026
/// keyboard's complete S4 readback after its current NuPhy firmware update.
public final class Kick75KeymapController: @unchecked Sendable {
    public static let vendorID = 0x19F5
    public static let productID = 0x1026
    public static let keymapByteCount = 1_472

    private static let getUseKeyMatrix: UInt8 = 0xB2
    private static let setUseKeyMatrix: UInt8 = 0xB3
    private static let chunkSize = 56
    private static let entriesPerLayer = 92
    private static let layerCount = 8
    private static let baseLayers = [0, 4]
    private static let bridgeFunctionRow = (1...12).map { UInt16(0x67 + $0) }
    private static let macOriginalFunctionRow: [UInt16] = [
        0x0069, 0x006A, 0x7E06, 0x7E07, 0x7E08, 0x7E16,
        0x00AC, 0x00AE, 0x00AB, 0x00A8, 0x00AA, 0x00A9,
    ]
    private static let windowsOriginalFunctionRow = (0x003A...0x0045).map(UInt16.init)
    private static let originalKnob: [(entry: Int, value: UInt16)] = [
        (74, 0x00A8), // press: mute
        (90, 0x00A9), // clockwise: volume up
        (91, 0x00AA), // counter-clockwise: volume down
    ]
    private static let bridgeKnob: [(entry: Int, value: UInt16)] = [
        (74, 0x0048), // press: Pause
        (90, 0x0046), // clockwise: Print Screen
        (91, 0x0047), // counter-clockwise: Scroll Lock
    ]

    public init() {}

    public static func hasBridgeProfile(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == keymapByteCount else { return false }
        for layer in baseLayers where row(in: bytes, layer: layer) != bridgeFunctionRow {
            return false
        }
        for layer in 0..<layerCount where knob(in: bytes, layer: layer) != bridgeKnob.map(\.value) {
            return false
        }
        return true
    }

    public static func isPlausibleKeymap(_ bytes: [UInt8]) -> Bool {
        (try? Kick75KeymapController().makeBridgeProfile(from: bytes)) != nil
    }

    public func readKeymap() throws -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(Self.keymapByteCount)
        for address in stride(from: 0, to: Self.keymapByteCount, by: Self.chunkSize) {
            let length = min(Self.chunkSize, Self.keymapByteCount - address)
            let response = try KeymapProtocolSession(
                expectedCommand: Self.getUseKeyMatrix,
                productIDs: [Self.productID]
            ).transact(
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

        let macRow = Self.row(in: original, layer: 0)
        guard macRow == Self.macOriginalFunctionRow || macRow == Self.bridgeFunctionRow else {
            let mismatch = macRow.enumerated().first {
                $0.element != Self.macOriginalFunctionRow[$0.offset]
            }?.offset ?? 0
            throw Air75KeymapError.incompatibleLayout(index: 1 + mismatch, value: macRow[mismatch])
        }
        let windowsRow = Self.row(in: original, layer: 4)
        guard windowsRow == Self.windowsOriginalFunctionRow || windowsRow == Self.bridgeFunctionRow else {
            let mismatch = zip(windowsRow, Self.windowsOriginalFunctionRow).enumerated().first {
                $0.element.0 != $0.element.1
            }?.offset ?? 0
            throw Air75KeymapError.incompatibleLayout(
                index: 4 * Self.entriesPerLayer + 1 + mismatch,
                value: windowsRow[mismatch]
            )
        }
        for layer in 0..<Self.layerCount {
            let current = Self.knob(in: original, layer: layer)
            guard current == Self.originalKnob.map(\.value) || current == Self.bridgeKnob.map(\.value) else {
                let mismatch = current.enumerated().first { offset, value in
                    value != Self.originalKnob[offset].value && value != Self.bridgeKnob[offset].value
                }?.offset ?? 0
                let entry = layer * Self.entriesPerLayer + Self.originalKnob[mismatch].entry
                throw Air75KeymapError.incompatibleLayout(index: entry, value: current[mismatch])
            }
        }

        var profile = original
        for layer in Self.baseLayers {
            for (offset, value) in Self.bridgeFunctionRow.enumerated() {
                Self.setKeycode(value, in: &profile,
                                entry: layer * Self.entriesPerLayer + offset + 1)
            }
        }
        for layer in 0..<Self.layerCount {
            for item in Self.bridgeKnob {
                Self.setKeycode(item.value, in: &profile,
                                entry: layer * Self.entriesPerLayer + item.entry)
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
            return Air75KeymapInstallResult(original: original, installed: profile,
                                            changedChunkAddresses: [])
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
        return Air75KeymapInstallResult(original: original, installed: profile,
                                        changedChunkAddresses: changed)
    }

    @discardableResult
    public func restore(_ bytes: [UInt8]) throws -> [UInt8] {
        guard Self.isPlausibleKeymap(bytes), !Self.hasBridgeProfile(bytes) else {
            throw Air75KeymapError.invalidLength
        }
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
            _ = try KeymapProtocolSession(
                expectedCommand: Self.setUseKeyMatrix,
                productIDs: [Self.productID]
            ).transact(
                command: Self.setUseKeyMatrix,
                length: UInt8(payload.count),
                address: UInt16(address),
                handle: 0,
                payload: payload
            )
            Thread.sleep(forTimeInterval: 0.06)
        }
    }

    private static func row(in bytes: [UInt8], layer: Int) -> [UInt16] {
        (1...12).map { keycode(in: bytes, entry: layer * entriesPerLayer + $0) }
    }

    private static func knob(in bytes: [UInt8], layer: Int) -> [UInt16] {
        originalKnob.map { keycode(in: bytes, entry: layer * entriesPerLayer + $0.entry) }
    }

    private static func keycode(in bytes: [UInt8], entry: Int) -> UInt16 {
        let offset = entry * 2
        return (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    private static func setKeycode(_ value: UInt16, in bytes: inout [UInt8], entry: Int) {
        let offset = entry * 2
        bytes[offset] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 1] = UInt8(value & 0xFF)
    }
}

/// Verified Node100 Low-profile ANSI keymap writer. This model reports an
/// independent 6x19 matrix plus five touch-zone entries (119 entries per
/// layer). Only the two base layers are changed: F1-F12 become the Bridge
/// usages and the touch zone's mute/volume gestures become three dedicated
/// reasoning controls. Fn-layer brightness and media gestures remain native.
public final class Node100LPANSIKeymapController: @unchecked Sendable {
    public static let vendorID = 0x19F5
    public static let productID = 0x1037
    public static let keymapByteCount = 1_904

    private static let getUseKeyMatrix: UInt8 = 0xB2
    private static let setUseKeyMatrix: UInt8 = 0xB3
    private static let chunkSize = 56
    private static let entriesPerLayer = 119
    private static let layerCount = 8
    private static let baseLayers = [0, 4]
    private static let bridgeFunctionRow = (1...12).map { UInt16(0x67 + $0) }
    private static let macOriginalFunctionRow: [UInt16] = [
        0x0069, 0x006A, 0x7E06, 0x7E07, 0x7E08, 0x7E16,
        0x00AC, 0x00AE, 0x00AB, 0x00A8, 0x00AA, 0x00A9,
    ]
    private static let windowsOriginalFunctionRow = (0x003A...0x0045).map(UInt16.init)
    private static let originalTouchControls: [(entry: Int, value: UInt16)] = [
        (115, 0x00A8), // double tap: mute
        (117, 0x00AA), // swipe left: volume down
        (118, 0x00A9), // swipe right: volume up
    ]
    private static let bridgeTouchControls: [(entry: Int, value: UInt16)] = [
        (115, 0x0048), // double tap: Pause / reasoning selector
        (117, 0x0047), // swipe left: Scroll Lock / reasoning down
        (118, 0x0046), // swipe right: Print Screen / reasoning up
    ]

    public init() {}

    public static func hasBridgeProfile(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == keymapByteCount else { return false }
        for layer in baseLayers where row(in: bytes, layer: layer) != bridgeFunctionRow {
            return false
        }
        for layer in baseLayers
        where touchControls(in: bytes, layer: layer) != bridgeTouchControls.map(\.value) {
            return false
        }
        return true
    }

    public static func isPlausibleKeymap(_ bytes: [UInt8]) -> Bool {
        (try? Node100LPANSIKeymapController().makeBridgeProfile(from: bytes)) != nil
    }

    public func readKeymap() throws -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(Self.keymapByteCount)
        for address in stride(from: 0, to: Self.keymapByteCount, by: Self.chunkSize) {
            let length = min(Self.chunkSize, Self.keymapByteCount - address)
            let response = try KeymapProtocolSession(
                expectedCommand: Self.getUseKeyMatrix,
                productIDs: [Self.productID]
            ).transact(
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

        try Self.validateRow(
            in: original,
            layer: 0,
            original: Self.macOriginalFunctionRow
        )
        try Self.validateRow(
            in: original,
            layer: 4,
            original: Self.windowsOriginalFunctionRow
        )
        for layer in Self.baseLayers {
            let current = Self.touchControls(in: original, layer: layer)
            guard current == Self.originalTouchControls.map(\.value)
                    || current == Self.bridgeTouchControls.map(\.value) else {
                let mismatch = current.enumerated().first { offset, value in
                    value != Self.originalTouchControls[offset].value
                        && value != Self.bridgeTouchControls[offset].value
                }?.offset ?? 0
                let entry = layer * Self.entriesPerLayer
                    + Self.originalTouchControls[mismatch].entry
                throw Air75KeymapError.incompatibleLayout(index: entry, value: current[mismatch])
            }
        }

        var profile = original
        for layer in Self.baseLayers {
            for (offset, value) in Self.bridgeFunctionRow.enumerated() {
                Self.setKeycode(
                    value,
                    in: &profile,
                    entry: layer * Self.entriesPerLayer + offset + 1
                )
            }
            for item in Self.bridgeTouchControls {
                Self.setKeycode(
                    item.value,
                    in: &profile,
                    entry: layer * Self.entriesPerLayer + item.entry
                )
            }
        }
        return profile
    }

    public func installBridgeProfile(
        expectedOriginal: [UInt8]? = nil
    ) throws -> Air75KeymapInstallResult {
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
            guard try readKeymap() == profile else {
                throw Air75KeymapError.verificationFailed
            }
        } catch {
            try? write(chunksAt: changed, from: original)
            Thread.sleep(forTimeInterval: 0.25)
            guard (try? readKeymap()) == original else {
                throw Air75KeymapError.restoreFailed
            }
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
        guard Self.isPlausibleKeymap(bytes), !Self.hasBridgeProfile(bytes) else {
            throw Air75KeymapError.invalidLength
        }
        let current = try readKeymap()
        let changed = changedChunks(from: current, to: bytes)
        try write(chunksAt: changed, from: bytes)
        Thread.sleep(forTimeInterval: 0.25)
        let readback = try readKeymap()
        guard readback == bytes else { throw Air75KeymapError.restoreFailed }
        return readback
    }

    private static func validateRow(
        in bytes: [UInt8],
        layer: Int,
        original: [UInt16]
    ) throws {
        let current = row(in: bytes, layer: layer)
        guard current == original || current == bridgeFunctionRow else {
            let mismatch = zip(current, original).enumerated().first {
                $0.element.0 != $0.element.1
            }?.offset ?? 0
            throw Air75KeymapError.incompatibleLayout(
                index: layer * entriesPerLayer + 1 + mismatch,
                value: current[mismatch]
            )
        }
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
            _ = try KeymapProtocolSession(
                expectedCommand: Self.setUseKeyMatrix,
                productIDs: [Self.productID]
            ).transact(
                command: Self.setUseKeyMatrix,
                length: UInt8(payload.count),
                address: UInt16(address),
                handle: 0,
                payload: payload
            )
            Thread.sleep(forTimeInterval: 0.06)
        }
    }

    private static func row(in bytes: [UInt8], layer: Int) -> [UInt16] {
        (1...12).map { keycode(in: bytes, entry: layer * entriesPerLayer + $0) }
    }

    private static func touchControls(in bytes: [UInt8], layer: Int) -> [UInt16] {
        originalTouchControls.map {
            keycode(in: bytes, entry: layer * entriesPerLayer + $0.entry)
        }
    }

    private static func keycode(in bytes: [UInt8], entry: Int) -> UInt16 {
        let offset = entry * 2
        return (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    private static func setKeycode(_ value: UInt16, in bytes: inout [UInt8], entry: Int) {
        let offset = entry * 2
        bytes[offset] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 1] = UInt8(value & 0xFF)
    }
}

private final class KeymapProtocolSession {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private let expectedCommand: UInt8
    private let productIDs: [Int]
    private var response: [UInt8]?

    init(expectedCommand: UInt8,
         productIDs: [Int] = [Air75V3KeymapController.productID,
                              Air75V3KeymapController.dongleProductID]) {
        self.expectedCommand = expectedCommand
        self.productIDs = productIDs
    }
    deinit { inputBuffer.deallocate() }

    func transact(command: UInt8, length: UInt8, address: UInt16, handle: UInt8,
                  payload: [UInt8]) throws -> [UInt8] {
        try NuPhyHIDOperationCoordinator.withExclusiveAccess {
            try transactLocked(command: command, length: length, address: address,
                               handle: handle, payload: payload)
        }
    }

    private func transactLocked(command: UInt8, length: UInt8, address: UInt16,
                                handle: UInt8, payload: [UInt8]) throws -> [UInt8] {
        let matches = productIDs.map { productID in
            [
                kIOHIDVendorIDKey: Air75V3KeymapController.vendorID,
                kIOHIDProductIDKey: productID,
                kIOHIDPrimaryUsagePageKey: 1,
                kIOHIDPrimaryUsageKey: 0,
            ]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else { throw Air75KeymapError.managerOpen(openResult) }
        defer {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        // 有线接口优先；键盘切到 2.4G 时由接收器接管同一协议。
        let ordered = devices.sorted { priority(of: $0) < priority(of: $1) }
        guard !ordered.isEmpty else { throw Air75KeymapError.deviceNotFound }

        var lastError: Error = Air75KeymapError.deviceNotFound
        for device in ordered {
            do {
                return try attempt(on: device, command: command, length: length,
                                   address: address, handle: handle, payload: payload)
            } catch let error as Air75KeymapError {
                // 会话密钥属于键盘固件本身，换接口不会消除冲突。
                if case .sessionKeyConflict = error { throw error }
                lastError = error
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func attempt(on device: IOHIDDevice, command: UInt8, length: UInt8,
                         address: UInt16, handle: UInt8, payload: [UInt8]) throws -> [UInt8] {
        response = nil
        inputBuffer.initialize(repeating: 0, count: 64)
        IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, 64, Self.inputReport,
                                               Unmanaged.passUnretained(self).toOpaque())
        var report = Self.makeReport(command: command, length: length, address: address,
                                     handle: handle, payload: payload)
        let reportCount = report.count
        let writeResult = report.withUnsafeMutableBytes { raw in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0,
                                 raw.bindMemory(to: UInt8.self).baseAddress!, reportCount)
        }
        guard writeResult == kIOReturnSuccess else { throw Air75KeymapError.writeFailed(writeResult) }

        let deadline = Date().addingTimeInterval(1.5)
        while response == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        guard let response else { throw Air75KeymapError.timeout(command: command) }
        guard response.count == 64, response[0] == 0xAA, response[1] == command else {
            throw Air75KeymapError.invalidResponse
        }
        let checksum = UInt8(response[4...].reduce(0) { ($0 + Int($1)) & 0xFF })
        guard checksum == response[3] else { throw Air75KeymapError.invalidChecksum }
        // 检测其他配置器（如 NuPhyIO）遗留的 0xEE 会话密钥：帧头 4-7 字节被同
        // 一个非零密钥 XOR 时立即报告冲突，避免把乱码写进键位表。
        let keyCandidates: Set<UInt8> = [
            response[4] ^ length,
            response[5] ^ UInt8(address & 0xFF),
            response[6] ^ UInt8((address >> 8) & 0xFF),
            response[7] ^ handle
        ]
        if keyCandidates.count == 1, let key = keyCandidates.first, key != 0 {
            throw Air75KeymapError.sessionKeyConflict(key)
        }
        if command == Air75V3KeymapController.getUseKeyMatrix {
            guard Int(response[4]) >= Int(length), response.count >= 8 + Int(length) else {
                throw Air75KeymapError.invalidResponse
            }
        }
        return response
    }

    private func priority(of device: IOHIDDevice) -> Int {
        let productID = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int) ?? -1
        return productIDs.firstIndex(of: productID) ?? productIDs.count
    }

    private static func makeReport(command: UInt8, length: UInt8, address: UInt16,
                                   handle: UInt8, payload: [UInt8]) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: 64)
        report[0] = 0x55
        report[1] = command
        report[4] = length
        report[5] = UInt8(address & 0xFF)
        report[6] = UInt8((address >> 8) & 0xFF)
        report[7] = handle
        for (index, byte) in payload.prefix(56).enumerated() { report[8 + index] = byte }
        report[3] = UInt8(report[4...].reduce(0) { ($0 + Int($1)) & 0xFF })
        return report
    }

    private static let inputReport: IOHIDReportCallback = { context, result, _, _, _, report, length in
        guard result == kIOReturnSuccess, let context, length == 64 else { return }
        let session = Unmanaged<KeymapProtocolSession>.fromOpaque(context).takeUnretainedValue()
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))
        guard bytes.count >= 2, bytes[0] == 0xAA, bytes[1] == session.expectedCommand else { return }
        session.response = bytes
    }
}
