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
    /// The mode macOS is using right now. `width`/`height` are the looks-like size.
    public var currentMode: DisplayModeSummary?

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
        defaultMode: ScaledMode?,
        currentMode: DisplayModeSummary? = nil
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
        self.currentMode = currentMode
    }

    /// Rebuild presets from the panel size captured before HiDPI was turned on.
    public func locked(to panel: PanelPixels) -> DisplaySnapshot {
        guard panel != self.panel else {
            return self
        }
        let presets = ResolutionPlan.presets(for: panel)
        var copy = self
        copy.panel = panel
        copy.presets = presets
        copy.defaultMode = ResolutionPlan.defaultPreset(for: panel, presets: presets)
        return copy
    }

    public var id: String {
        "\(key.vendorID)-\(key.productID)-\(key.serialNumber)-\(key.unitNumber)-\(displayID)"
    }

    public var isEligible: Bool {
        !isBuiltIn && !isOurs && defaultMode != nil
    }
}
