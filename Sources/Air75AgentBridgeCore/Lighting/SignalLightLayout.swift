import Foundation

/// Verified D8 index layout for the ANSI Air75 V3. The visible-key order is
/// derived from NuPhy's official NuPhyIO layout; the three hidden knob entries
/// after Insert are removed by the firmware's `skipPos/skipSize` rule.
public enum SignalLightLayout {
    /// D8 colors persist independently from ordinary backlight animation.
    /// A short-lived first-run bug assigned Agent 3 to Tab (index 30), so the
    /// Air75 driver explicitly clears it unless Tab is intentionally active.
    public static func staleManagedIndices(layoutID: String?) -> Set<Int> {
        layoutID == "nuphy.air75-v3.ansi-d8" ? [30] : []
    }

    public static func index(
        layoutID: String?,
        usagePage: Int,
        usage: Int
    ) -> Int? {
        guard layoutID == "nuphy.air75-v3.ansi-d8", usagePage == 0x07 else {
            return nil
        }
        return air75V3ANSI[usage]
    }

    private static let air75V3ANSI: [Int: Int] = {
        var result: [Int: Int] = [:]

        result[0x29] = 0 // Esc
        for offset in 0..<12 {
            result[0x3A + offset] = 1 + offset // native F1...F12
            result[0x68 + offset] = 1 + offset // Bridge F13...F24 layer
        }
        result[0x46] = 13 // Print Screen / screenshot key
        result[0x49] = 14 // Insert

        result[0x35] = 15 // `
        for offset in 0..<10 { result[0x1E + offset] = 16 + offset } // 1...0
        result[0x2D] = 26
        result[0x2E] = 27
        result[0x2A] = 28
        result[0x4B] = 29 // Page Up

        result[0x2B] = 30 // Tab
        let qwertyUsages = [0x14, 0x1A, 0x08, 0x15, 0x17, 0x1C, 0x18, 0x0C, 0x12, 0x13]
        for (offset, usage) in qwertyUsages.enumerated() { result[usage] = 31 + offset }
        result[0x2F] = 41
        result[0x30] = 42
        result[0x28] = 43 // ANSI Return
        result[0x4E] = 44 // Page Down

        result[0x39] = 45 // Caps Lock
        let homeRow = [0x04, 0x16, 0x07, 0x09, 0x0A, 0x0B, 0x0D, 0x0E, 0x0F]
        for (offset, usage) in homeRow.enumerated() { result[usage] = 46 + offset }
        result[0x33] = 55
        result[0x34] = 56
        result[0x31] = 57
        result[0x4A] = 58 // Home

        let bottomLetters = [0x1D, 0x1B, 0x06, 0x19, 0x05, 0x11, 0x10]
        for (offset, usage) in bottomLetters.enumerated() { result[usage] = 61 + offset }
        result[0x36] = 68
        result[0x37] = 69
        result[0x38] = 70
        result[0x52] = 72 // Up
        result[0x4D] = 73 // End
        result[0x2C] = 77 // Space
        result[0x50] = 81 // Left
        result[0x51] = 82 // Down
        result[0x4F] = 83 // Right
        return result
    }()
}
