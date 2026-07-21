import Foundation

/// Pure encoder/decoder for NuPhy's 64-byte S4 configuration protocol.
///
/// NuPhyIO establishes a one-byte XOR session key with command `0xEE`.
/// Firmware 1.0.16.6 may leave the four routing bytes in a response plain
/// while still encrypting its payload, whereas older firmware encrypts both.
/// The codec accepts both official response layouts but always emits the
/// fully keyed request layout used by NuPhyIO after the handshake.
public enum NuPhyS4ProtocolCodec {
    public static let reportSize = 64
    public static let maximumPayloadSize = 56
    public static let setSecretKeyCommand: UInt8 = 0xEE

    public enum DecodeError: Error, Equatable {
        case invalidFrame
        case invalidChecksum
        case sessionKeyMismatch(UInt8)
    }

    public struct Handshake: Equatable, Sendable {
        public let report: [UInt8]
        public let sessionKey: UInt8

        public init(challenge: [UInt8]) {
            precondition(challenge.count == maximumPayloadSize)
            var normalized = challenge
            if normalized[20] == 0 { normalized[20] = 0xAA }

            var report = [UInt8](repeating: 0, count: reportSize)
            report[0] = 0x55
            report[1] = setSecretKeyCommand
            report.replaceSubrange(8..<reportSize, with: normalized)
            report[3] = checksum(report)

            self.report = report
            self.sessionKey = normalized[20]
        }
    }

    public static func randomHandshake() -> Handshake {
        var generator = SystemRandomNumberGenerator()
        let challenge = (0..<maximumPayloadSize).map { _ in
            UInt8.random(in: .min ... .max, using: &generator)
        }
        return Handshake(challenge: challenge)
    }

    public static func makeReport(
        command: UInt8,
        length: UInt8,
        address: UInt16,
        handle: UInt8,
        payload: [UInt8] = [],
        sessionKey: UInt8
    ) -> [UInt8] {
        precondition(Int(length) <= maximumPayloadSize)
        precondition(payload.count <= maximumPayloadSize)

        var report = [UInt8](repeating: 0, count: reportSize)
        report[0] = 0x55
        report[1] = command
        report[4] = length ^ sessionKey
        report[5] = UInt8(address & 0xFF) ^ sessionKey
        report[6] = UInt8((address >> 8) & 0xFF) ^ sessionKey
        report[7] = handle ^ sessionKey
        for (index, byte) in payload.prefix(maximumPayloadSize).enumerated() {
            report[8 + index] = byte ^ sessionKey
        }
        report[3] = checksum(report)
        return report
    }

    /// Validates the unencrypted 0xEE acknowledgement. The firmware may
    /// transform the challenge in its response, so session correctness is
    /// confirmed by the first keyed command rather than by echo assumptions.
    public static func validateHandshakeAcknowledgement(_ response: [UInt8]) throws {
        guard response.count == reportSize,
              response[0] == 0xAA,
              response[1] == setSecretKeyCommand else {
            throw DecodeError.invalidFrame
        }
        guard checksum(response) == response[3] else {
            throw DecodeError.invalidChecksum
        }
    }

    /// Returns a normalized plaintext response. Header bytes 4...7 and the
    /// requested payload bytes are decoded in the returned frame.
    public static func decodeResponse(
        _ response: [UInt8],
        command: UInt8,
        length: UInt8,
        address: UInt16,
        handle: UInt8,
        sessionKey: UInt8
    ) throws -> [UInt8] {
        guard response.count == reportSize,
              response[0] == 0xAA,
              response[1] == command else {
            throw DecodeError.invalidFrame
        }
        guard checksum(response) == response[3] else {
            throw DecodeError.invalidChecksum
        }

        let expectedHeader: [UInt8] = [
            length,
            UInt8(address & 0xFF),
            UInt8((address >> 8) & 0xFF),
            handle,
        ]
        let rawHeader = Array(response[4...7])
        let keyedHeader = rawHeader.map { $0 ^ sessionKey }

        guard rawHeader == expectedHeader || keyedHeader == expectedHeader else {
            let candidates = Set(zip(rawHeader, expectedHeader).map(^))
            if candidates.count == 1, let candidate = candidates.first, candidate != 0 {
                throw DecodeError.sessionKeyMismatch(candidate)
            }
            throw DecodeError.invalidFrame
        }
        guard Int(length) <= maximumPayloadSize,
              response.count >= 8 + Int(length) else {
            throw DecodeError.invalidFrame
        }

        var decoded = response
        decoded.replaceSubrange(4...7, with: expectedHeader)
        if sessionKey != 0 {
            for index in 8..<(8 + Int(length)) {
                decoded[index] ^= sessionKey
            }
        }
        return decoded
    }

    public static func checksum(_ report: [UInt8]) -> UInt8 {
        UInt8(report.dropFirst(4).reduce(0) { ($0 + Int($1)) & 0xFF })
    }
}
