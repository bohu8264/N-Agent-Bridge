import Foundation

/// Verified D8 index layout for the ANSI Air75 V3. The visible-key order is
/// derived from NuPhy's official NuPhyIO device layout; the three hidden knob
/// entries after Insert are removed by the device's `skipPos/skipSize` rule.
/// Index 0 (Esc) and 1...6 (F1...F6) have also been confirmed on hardware.
public enum SignalLightLayout {
    public static func index(
        layoutID: String?,
        usagePage: Int,
        usage: Int
    ) -> Int? {
        guard usagePage == 0x07 else { return nil }
        switch layoutID {
        case "nuphy.air75-v3.ansi-d8":
            return air75V3ANSI[usage]
        case "nuphy.kick75.ansi-d8":
            return kick75ANSI[usage]
        default:
            return nil
        }
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
        // HID alphabet order differs from the physical A...L row.
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

    /// Kick75's official NuPhyIO layout contains three hidden encoder entries
    /// at source indexes 14...16. Firmware D8 indexes use the visible-key
    /// order after those entries are removed. Hardware confirms index 0 is Esc
    /// and 1...12 are F1...F12; Q (official source index 33) is therefore 30.
    private static let kick75ANSI: [Int: Int] = {
        var result: [Int: Int] = [
            0x29: 0,  // Esc
            0x4C: 13, // Delete
            0x35: 14, // `
            0x2D: 25, // -
            0x2E: 26, // =
            0x2A: 27, // Backspace
            0x4A: 28, // Home
            0x2B: 29, // Tab
            0x2F: 40, // [
            0x30: 41, // ]
            0x31: 42, // \
            0x4B: 43, // Page Up
            0x39: 44, // Caps Lock
            0x33: 54, // ;
            0x34: 55, // '
            0x28: 56, // Return
            0x4E: 57, // Page Down
            0xE1: 58, // Left Shift
            0x36: 66, // ,
            0x37: 67, // .
            0x38: 68, // /
            0xE5: 69, // Right Shift
            0x52: 70, // Up
            0xE0: 71, // Left Control
            0xE3: 72, // Left Command
            0xE2: 73, // Left Option
            0x2C: 74, // Space
            0xE6: 75, // Right Option
            // Index 76 is the firmware Fn key and has no standard HID usage.
            0x50: 77, // Left
            0x51: 78, // Down
            0x4F: 79, // Right
        ]
        for offset in 0..<12 {
            result[0x3A + offset] = 1 + offset
            result[0x68 + offset] = 1 + offset
        }
        for offset in 0..<10 { result[0x1E + offset] = 15 + offset } // 1...0
        let qwerty = [0x14, 0x1A, 0x08, 0x15, 0x17, 0x1C, 0x18, 0x0C, 0x12, 0x13]
        for (offset, usage) in qwerty.enumerated() { result[usage] = 30 + offset }
        let homeRow = [0x04, 0x16, 0x07, 0x09, 0x0A, 0x0B, 0x0D, 0x0E, 0x0F]
        for (offset, usage) in homeRow.enumerated() { result[usage] = 45 + offset }
        let bottomLetters = [0x1D, 0x1B, 0x06, 0x19, 0x05, 0x11, 0x10]
        for (offset, usage) in bottomLetters.enumerated() { result[usage] = 59 + offset }
        return result
    }()
}
