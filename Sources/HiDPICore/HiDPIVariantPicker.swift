import Foundation

/// The toggle flips the current panel between its 1× native mode and the 2× mode
/// with the same looks-like size. It does not pick a smaller scaled resolution.
public enum HiDPIVariantPicker {
    public static func hiDPIMode(
        panel: PanelPixels,
        among modes: [DisplayModeSummary]
    ) -> DisplayModeSummary? {
        ModeMatching.bestHiDPIMode(
            among: modes,
            logicalWidth: panel.width,
            logicalHeight: panel.height,
            refreshRate: 60
        )
    }

    public static func lowDPIMode(
        panel: PanelPixels,
        among modes: [DisplayModeSummary]
    ) -> DisplayModeSummary? {
        let matches = modes.filter {
            $0.width == panel.width
                && $0.height == panel.height
                && $0.pixelWidth == panel.width
                && $0.pixelHeight == panel.height
        }
        return matches.max { $0.refreshRate < $1.refreshRate }
    }
}
