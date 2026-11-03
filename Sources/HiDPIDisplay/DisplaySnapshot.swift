import CoreGraphics
import Foundation
import HiDPICore

public struct DisplaySnapshot: Equatable, Identifiable, Sendable {
    public var displayID: CGDirectDisplayID
    public var key: DisplayKey
    public var name: String
    public var panel: PanelPixels
    public var refreshRate: Double
    public var frameMinX: Double
    public var isBuiltIn: Bool
    public var isOurs: Bool
    public var presets: [ScaledMode]
    public var defaultMode: ScaledMode?

    public init(
        displayID: CGDirectDisplayID,
        key: DisplayKey,
        name: String,
        panel: PanelPixels,
        refreshRate: Double,
        frameMinX: Double,
        isBuiltIn: Bool,
        isOurs: Bool,
        presets: [ScaledMode],
        defaultMode: ScaledMode?
    ) {
        self.displayID = displayID
        self.key = key
        self.name = name
        self.panel = panel
        self.refreshRate = refreshRate
        self.frameMinX = frameMinX
        self.isBuiltIn = isBuiltIn
        self.isOurs = isOurs
        self.presets = presets
        self.defaultMode = defaultMode
    }

    public var id: String {
        "\(key.vendorID)-\(key.productID)-\(key.serialNumber)-\(key.unitNumber)-\(displayID)"
    }

    public var isEligible: Bool {
        !isBuiltIn && !isOurs && defaultMode != nil
    }
}
