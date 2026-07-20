import Foundation

public enum DeviceFingerprintMatcher {
    public static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    public static func classify(
        vendorID: Int,
        productID: Int,
        product: String,
        manufacturer: String?,
        transport: ConnectionTransport,
        usagePage: Int,
        usage: Int,
        profile: DeviceProfile,
        confirmedFingerprint: DeviceFingerprint?
    ) -> RecognitionResult {
        guard profile.allowedUsagePages.contains(usagePage) else { return .rejected }

        let normalizedProduct = normalize(product)
        let productMatch = profile.productAliases.map(normalize).contains(normalizedProduct)
        let manufacturerMatch = manufacturer.map(normalize).map { value in
            profile.manufacturerAliases.map(normalize).contains(where: { value.contains($0) })
        } ?? false

        if transport == .usb,
           profile.usbIdentities.contains(where: { $0.vendorID == vendorID && $0.productID == productID }),
           productMatch {
            return .recognized(confidence: manufacturerMatch ? 100 : 95)
        }

        if transport == .bluetooth, productMatch, usagePage == 0x01, [0x06, 0x02, 0x0C].contains(usage) {
            if profile.bluetoothVendorIDs.contains(vendorID) && manufacturerMatch {
                return .recognized(confidence: 95)
            }
            if let confirmedFingerprint,
               confirmedFingerprint.normalizedProduct == normalizedProduct,
               confirmedFingerprint.confirmedBluetoothAlias == "\(vendorID):\(productID)" {
                return .recognized(confidence: 100)
            }
            return .bluetoothCandidate(confidence: manufacturerMatch || profile.bluetoothVendorIDs.contains(vendorID) ? 80 : 65)
        }

        return .rejected
    }

    public static func fingerprint(for interface: HIDInterfaceSnapshot, confirmedBluetoothAlias: String? = nil) -> DeviceFingerprint {
        DeviceFingerprint(
            vendorID: interface.vendorID,
            productID: interface.productID,
            normalizedProduct: normalize(interface.productName),
            normalizedManufacturer: interface.manufacturer.map(normalize),
            serialNumber: interface.serialNumber,
            confirmedBluetoothAlias: confirmedBluetoothAlias
        )
    }
}
