import Foundation

/// Property list written for one physical panel.
/// The marker key lets reset delete only files this app created.
public enum DisplayOverrideDocument {
    public static let markerKey = "com.yosong.mac-hidpi"
    /// About 256 pixels per inch, the value one-key-hidpi writes so WindowServer
    /// will offer the scaled modes.
    public static let targetPixelsPerMillimeter = 10.0699301

    public static func propertyList(
        vendorID: UInt32,
        productID: UInt32,
        name: String,
        panel: PanelPixels,
        modes: [ScaledMode]
    ) throws -> Data {
        let native = ResolutionPlan.defaultPreset(for: panel, presets: modes)
        var scaleData: [Data] = []
        var seen = Set<Data>()
        for mode in modes {
            for entry in ScaleResolutionCodec.entries(for: mode) {
                let data = ScaleResolutionCodec.encode(entry)
                if seen.insert(data).inserted {
                    scaleData.append(data)
                }
            }
        }
        var root: [String: Any] = [
            "DisplayVendorID": Int(vendorID),
            "DisplayProductID": Int(productID),
            "DisplayProductName": name,
            "DisplayPixelDimensions": ScaleResolutionCodec.encode(
                .lowDPI(width: panel.width, height: panel.height)
            ),
            "scale-resolutions": scaleData,
            markerKey: true,
            "target-default-ppmm": targetPixelsPerMillimeter,
        ]
        if let native {
            root["default-resolution"] = ScaleResolutionCodec.encode(
                .hiDPI(pixelWidth: native.pixelWidth, pixelHeight: native.pixelHeight)
            )
        }
        return try PropertyListSerialization.data(
            fromPropertyList: root,
            format: .xml,
            options: 0
        )
    }

    public static func containsMarker(_ data: Data) -> Bool {
        guard
            let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return false
        }
        return (root[markerKey] as? Bool) == true
    }
}
