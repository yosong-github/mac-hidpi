import CoreGraphics
import Foundation
import HiDPICore

/// Switches the physical panel with the public mode list. BetterDisplay uses the
/// private `CGSConfigureDisplayMode` index; the same modes are visible here once
/// `kCGDisplayShowDuplicateLowResolutionModes` is set, including the 2× variant.
enum RealDisplayModeSwitcher {
    static func modes(for displayID: CGDirectDisplayID) -> [DisplayModeSummary] {
        DisplayModeController.summaries(for: displayID)
    }

    static func applyHiDPI(displayID: CGDirectDisplayID, panel: PanelPixels) -> Result<DisplayModeSummary, HiDPIError> {
        apply(displayID: displayID, panel: panel, hiDPI: true)
    }

    static func applyLowDPI(displayID: CGDirectDisplayID, panel: PanelPixels) -> Result<DisplayModeSummary, HiDPIError> {
        apply(displayID: displayID, panel: panel, hiDPI: false)
    }

    private static func apply(
        displayID: CGDirectDisplayID,
        panel: PanelPixels,
        hiDPI: Bool
    ) -> Result<DisplayModeSummary, HiDPIError> {
        let available = modes(for: displayID)
        let match =
            hiDPI
            ? HiDPIVariantPicker.hiDPIMode(panel: panel, among: available)
            : HiDPIVariantPicker.lowDPIMode(panel: panel, among: available)
        guard let match else {
            return .failure(
                .modeNotFound(
                    requested: "\(panel.width)x\(panel.height) \(hiDPI ? "2x" : "1x")",
                    available: ModeMatching.describe(available)
                )
            )
        }
        let result =
            hiDPI
            ? DisplayModeController.applyBest(
                displayID: displayID,
                logicalWidth: panel.width,
                logicalHeight: panel.height,
                refreshRate: match.refreshRate
            )
            : DisplayModeController.applyExact(
                displayID: displayID,
                width: panel.width,
                height: panel.height,
                pixelWidth: panel.width,
                pixelHeight: panel.height,
                refreshRate: match.refreshRate
            )
        if case let .failure(error) = result {
            return .failure(error)
        }
        return .success(match)
    }
}
