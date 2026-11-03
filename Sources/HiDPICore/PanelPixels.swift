import Foundation

/// Pixel size of a physical panel in its current orientation.
public struct PanelPixels: Equatable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var aspectRatio: Double {
        guard height > 0 else {
            return 0
        }
        return Double(width) / Double(height)
    }
}

/// A Retina-style mode: UI layout at `logical` points, rendered at `scale`×.
public struct ScaledMode: Equatable, Hashable, Codable, Identifiable, Sendable {
    public var logicalWidth: Int
    public var logicalHeight: Int
    public var scale: Int

    public init(logicalWidth: Int, logicalHeight: Int, scale: Int = 2) {
        self.logicalWidth = logicalWidth
        self.logicalHeight = logicalHeight
        self.scale = scale
    }

    public var id: String {
        "\(logicalWidth)x\(logicalHeight)@\(scale)"
    }

    public var pixelWidth: Int {
        logicalWidth * scale
    }

    public var pixelHeight: Int {
        logicalHeight * scale
    }

    public func isPixelAligned(with panel: PanelPixels) -> Bool {
        pixelWidth == panel.width && pixelHeight == panel.height
    }
}

/// Stable identity of a physical display. `CGDirectDisplayID` is not stable across replug.
public struct DisplayKey: Equatable, Hashable, Codable, Sendable {
    public var vendorID: UInt32
    public var productID: UInt32
    public var serialNumber: UInt32
    public var unitNumber: UInt32

    public init(vendorID: UInt32, productID: UInt32, serialNumber: UInt32, unitNumber: UInt32) {
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.unitNumber = unitNumber
    }
}

/// One timing passed to `CGVirtualDisplayMode`.
public struct VirtualMode: Equatable, Hashable, Sendable {
    public var width: Int
    public var height: Int
    public var refreshRate: Double

    public init(width: Int, height: Int, refreshRate: Double) {
        self.width = width
        self.height = height
        self.refreshRate = refreshRate
    }
}

/// Parameters for one `CGVirtualDisplay` creation attempt.
public struct VirtualDisplaySpec: Equatable, Sendable {
    public var name: String
    public var maxPixelsWide: Int
    public var maxPixelsHigh: Int
    public var widthMillimeters: Double
    public var heightMillimeters: Double
    public var vendorID: UInt32
    public var productID: UInt32
    public var serialNumber: UInt32
    public var hiDPI: Bool
    public var modes: [VirtualMode]

    public init(
        name: String,
        maxPixelsWide: Int,
        maxPixelsHigh: Int,
        widthMillimeters: Double,
        heightMillimeters: Double,
        vendorID: UInt32,
        productID: UInt32,
        serialNumber: UInt32,
        hiDPI: Bool,
        modes: [VirtualMode]
    ) {
        self.name = name
        self.maxPixelsWide = maxPixelsWide
        self.maxPixelsHigh = maxPixelsHigh
        self.widthMillimeters = widthMillimeters
        self.heightMillimeters = heightMillimeters
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.hiDPI = hiDPI
        self.modes = modes
    }
}

/// How `CGVirtualDisplayMode` width/height are interpreted when `hiDPI` is set.
public enum VirtualDisplayAttemptKind: Equatable, Sendable {
    /// Mode size is the logical point size. Chromium's virtual display helper does this:
    /// with hiDPI enabled, a 1920×1080 mode on a 3840×2160 framebuffer is the Retina mode.
    case logicalPoints
    /// Mode size is the framebuffer. Some builds advertise a half-point HiDPI mode from that.
    case framebufferPixels
}

public struct VirtualDisplayAttempt: Equatable, Sendable {
    public var kind: VirtualDisplayAttemptKind
    public var spec: VirtualDisplaySpec

    public init(kind: VirtualDisplayAttemptKind, spec: VirtualDisplaySpec) {
        self.kind = kind
        self.spec = spec
    }
}
