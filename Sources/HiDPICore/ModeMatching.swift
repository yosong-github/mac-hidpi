import Foundation

/// A display mode reduced to the fields the matcher needs. CoreGraphics stays out of this module.
public struct DisplayModeSummary: Equatable, Hashable, Sendable {
    public var width: Int
    public var height: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var refreshRate: Double

    public init(width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, refreshRate: Double) {
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
    }

    public var isHiDPI: Bool {
        pixelWidth >= width * 2 && pixelHeight >= height * 2 && width > 0 && height > 0
    }

    public var debugLine: String {
        "\(width)x\(height) pixels \(pixelWidth)x\(pixelHeight) @ \(refreshRate)"
    }
}

public enum ModeMatching {
    /// Prefer an exact 2× mode at the requested logical size, then the closest refresh rate.
    public static func bestHiDPIMode(
        among modes: [DisplayModeSummary],
        logicalWidth: Int,
        logicalHeight: Int,
        refreshRate: Double
    ) -> DisplayModeSummary? {
        let targetRefresh = ResolutionPlan.normalizedRefreshRate(refreshRate)
        let matches = modes.filter { isExactHiDPI($0, logicalWidth: logicalWidth, logicalHeight: logicalHeight) }
        return matches.min { lhs, rhs in
            let left = abs(lhs.refreshRate - targetRefresh)
            let right = abs(rhs.refreshRate - targetRefresh)
            if left == right {
                return lhs.refreshRate > rhs.refreshRate
            }
            return left < right
        }
    }

    /// Point size matches the request and the framebuffer is exactly twice that.
    /// A 2560×1440 mode whose pixels are also 2560×1440 is rejected.
    public static func isExactHiDPI(
        _ mode: DisplayModeSummary,
        logicalWidth: Int,
        logicalHeight: Int
    ) -> Bool {
        mode.width == logicalWidth
            && mode.height == logicalHeight
            && mode.pixelWidth == logicalWidth * 2
            && mode.pixelHeight == logicalHeight * 2
    }

    public static func describe(_ modes: [DisplayModeSummary]) -> String {
        if modes.isEmpty {
            return "(none)"
        }
        return modes.map(\.debugLine).joined(separator: "; ")
    }
}
