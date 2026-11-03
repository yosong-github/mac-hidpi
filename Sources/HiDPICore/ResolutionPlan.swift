import Foundation

/// Builds the HiDPI ladder for a panel and the virtual-display descriptors that request one step.
///
/// For a 2560×1440 panel the ladder includes the sizes this app is built around:
/// 2048×1152, 1920×1080, 1706×960, 1600×900, and pixel-aligned 1280×720.
/// Each logical size is rendered at 2× and the result is mirrored onto the panel.
public enum ResolutionPlan {
    /// Vendor ID stamped on virtual displays we create (`HD`).
    public static let virtualVendorID: UInt32 = 0x4844

    /// Reported density. High enough that macOS treats the virtual panel as Retina.
    public static let assumedPPI: Double = 220

    public static let maxFramebufferWidth = 7680
    public static let maxFramebufferHeight = 4320
    public static let minLogicalWidth = 640
    public static let minLogicalHeight = 480

    /// Fractions of the panel's native pixels, as exact ratios.
    /// 4/5, 3/4, 2/3, 5/8, 1/2 → on 2560×1440: 2048, 1920, 1706, 1600, 1280 wide.
    static let factors: [(numerator: Int, denominator: Int)] = [
        (4, 5),
        (3, 4),
        (2, 3),
        (5, 8),
        (1, 2),
    ]

    public static func presets(for panel: PanelPixels) -> [ScaledMode] {
        guard panel.width > 0, panel.height > 0 else {
            return []
        }
        var modes: [ScaledMode] = []
        var seen = Set<String>()
        for factor in factors {
            let logicalWidth = nearestEven(
                pixels: panel.width,
                numerator: factor.numerator,
                denominator: factor.denominator
            )
            let logicalHeight = nearestEven(
                pixels: panel.height,
                numerator: factor.numerator,
                denominator: factor.denominator
            )
            guard let mode = makeMode(logicalWidth: logicalWidth, logicalHeight: logicalHeight) else {
                continue
            }
            if seen.insert(mode.id).inserted {
                modes.append(mode)
            }
        }
        if modes.isEmpty {
            let logicalWidth = nearestEven(pixels: panel.width, numerator: 1, denominator: 2)
            let logicalHeight = nearestEven(pixels: panel.height, numerator: 1, denominator: 2)
            if let mode = makeMode(logicalWidth: logicalWidth, logicalHeight: logicalHeight) {
                modes.append(mode)
            }
        }
        return modes.sorted { lhs, rhs in
            if lhs.logicalWidth == rhs.logicalWidth {
                return lhs.logicalHeight > rhs.logicalHeight
            }
            return lhs.logicalWidth > rhs.logicalWidth
        }
    }

    /// The step closest to 75% of the panel width. On 2560×1440 that is 1920×1080.
    public static func defaultPreset(for panel: PanelPixels, presets: [ScaledMode]) -> ScaledMode? {
        guard panel.width > 0 else {
            return presets.first
        }
        let target = nearestEven(pixels: panel.width, numerator: 3, denominator: 4)
        return presets.min { lhs, rhs in
            let left = abs(lhs.logicalWidth - target)
            let right = abs(rhs.logicalWidth - target)
            if left == right {
                return lhs.logicalWidth > rhs.logicalWidth
            }
            return left < right
        }
    }

    public static func normalizedRefreshRate(_ hertz: Double) -> Double {
        guard hertz.isFinite else {
            return 60
        }
        let rounded = hertz.rounded()
        if rounded < 30 || rounded > 240 {
            return 60
        }
        return rounded
    }

    public static func sanitizedDisplayName(_ raw: String) -> String {
        let collapsed =
            raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = collapsed.isEmpty ? "Display" : collapsed
        if base.count <= 40 {
            return base
        }
        return String(base.prefix(40))
    }

    public static func virtualIdentity(for key: DisplayKey) -> (productID: UInt32, serialNumber: UInt32) {
        let product = fnv1a([key.vendorID, key.productID, key.unitNumber, 0x5044])
        let serial = fnv1a([key.vendorID, key.productID, key.serialNumber, key.unitNumber, 0x534E])
        return (product == 0 ? 1 : product, serial == 0 ? 1 : serial)
    }

    /// Two creation attempts for one chosen HiDPI step. The engine keeps the first that
    /// actually advertises a 2× mode of the requested logical size.
    public static func attempts(
        displayName: String,
        panel: PanelPixels,
        mode: ScaledMode,
        refreshRate: Double,
        identity: DisplayKey
    ) -> [VirtualDisplayAttempt] {
        let refresh = normalizedRefreshRate(refreshRate)
        let ids = virtualIdentity(for: identity)
        let name = "HiDPI \(sanitizedDisplayName(displayName))"
        let pixelWidth = mode.pixelWidth
        let pixelHeight = mode.pixelHeight
        let logical = VirtualMode(width: mode.logicalWidth, height: mode.logicalHeight, refreshRate: refresh)
        let pixels = VirtualMode(width: pixelWidth, height: pixelHeight, refreshRate: refresh)
        return [
            VirtualDisplayAttempt(
                kind: .logicalPoints,
                spec: spec(
                    name: name,
                    mode: logical,
                    pixelWidth: pixelWidth,
                    pixelHeight: pixelHeight,
                    productID: ids.productID,
                    serialNumber: ids.serialNumber
                )
            ),
            VirtualDisplayAttempt(
                kind: .framebufferPixels,
                spec: spec(
                    name: name,
                    mode: pixels,
                    pixelWidth: pixelWidth,
                    pixelHeight: pixelHeight,
                    productID: ids.productID,
                    serialNumber: ids.serialNumber
                )
            ),
        ]
    }

    public static func resolveSavedMode(
        logicalWidth: Int,
        logicalHeight: Int,
        presets: [ScaledMode]
    ) -> ScaledMode? {
        if let exact = presets.first(where: { $0.logicalWidth == logicalWidth && $0.logicalHeight == logicalHeight }) {
            return exact
        }
        return nil
    }

    static func nearestEven(pixels: Int, numerator: Int, denominator: Int) -> Int {
        guard pixels > 0, numerator > 0, denominator > 0 else {
            return 0
        }
        let scaled = pixels * numerator
        var nearest = (scaled + denominator / 2) / denominator
        if nearest % 2 != 0 {
            let down = nearest - 1
            let up = nearest + 1
            let downDelta = abs(down * denominator - scaled)
            let upDelta = abs(up * denominator - scaled)
            nearest = downDelta <= upDelta ? down : up
        }
        return max(nearest, 2)
    }

    private static func makeMode(logicalWidth: Int, logicalHeight: Int) -> ScaledMode? {
        let pixelWidth = logicalWidth * 2
        let pixelHeight = logicalHeight * 2
        guard logicalWidth >= minLogicalWidth, logicalHeight >= minLogicalHeight else {
            return nil
        }
        guard pixelWidth <= maxFramebufferWidth, pixelHeight <= maxFramebufferHeight else {
            return nil
        }
        guard logicalWidth % 2 == 0, logicalHeight % 2 == 0 else {
            return nil
        }
        return ScaledMode(logicalWidth: logicalWidth, logicalHeight: logicalHeight, scale: 2)
    }

    private static func spec(
        name: String,
        mode: VirtualMode,
        pixelWidth: Int,
        pixelHeight: Int,
        productID: UInt32,
        serialNumber: UInt32
    ) -> VirtualDisplaySpec {
        VirtualDisplaySpec(
            name: name,
            maxPixelsWide: pixelWidth,
            maxPixelsHigh: pixelHeight,
            widthMillimeters: millimeters(pixels: pixelWidth),
            heightMillimeters: millimeters(pixels: pixelHeight),
            vendorID: virtualVendorID,
            productID: productID,
            serialNumber: serialNumber,
            hiDPI: true,
            modes: [mode]
        )
    }

    static func millimeters(pixels: Int, ppi: Double = assumedPPI) -> Double {
        guard ppi > 0 else {
            return 0
        }
        return Double(pixels) / ppi * 25.4
    }

    /// Deterministic FNV-1a over little-endian bytes of each word. `Hasher` is per-process.
    static func fnv1a(_ words: [UInt32]) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for word in words {
            for shift in [UInt32(0), 8, 16, 24] {
                let byte = (word >> shift) & 0xFF
                hash ^= byte
                hash = hash &* 16_777_619
            }
        }
        return hash
    }
}
