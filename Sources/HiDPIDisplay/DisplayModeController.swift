import CoreGraphics
import Foundation
import HiDPICore

enum DisplayModeController {
    static func summaries(for displayID: CGDirectDisplayID) -> [DisplayModeSummary] {
        cgModes(for: displayID).map(summary(of:))
    }

    static func applyBest(
        displayID: CGDirectDisplayID,
        logicalWidth: Int,
        logicalHeight: Int,
        refreshRate: Double
    ) -> Result<Void, HiDPIError> {
        let pairs = cgModes(for: displayID).map { mode in
            (mode: mode, summary: summary(of: mode))
        }
        guard
            let best =
                ModeMatching.bestHiDPIMode(
                    among: pairs.map(\.summary),
                    logicalWidth: logicalWidth,
                    logicalHeight: logicalHeight,
                    refreshRate: refreshRate
                )
        else {
            return .failure(
                .modeNotFound(
                    requested: "\(logicalWidth)x\(logicalHeight)",
                    available: ModeMatching.describe(pairs.map(\.summary))
                )
            )
        }
        guard let match = pairs.first(where: { $0.summary == best }) else {
            return .failure(
                .modeNotFound(
                    requested: "\(logicalWidth)x\(logicalHeight)",
                    available: ModeMatching.describe(pairs.map(\.summary))
                )
            )
        }
        return apply(mode: match.mode, displayID: displayID)
    }

    private static func apply(mode: CGDisplayMode, displayID: CGDirectDisplayID) -> Result<Void, HiDPIError> {
        var config: CGDisplayConfigRef?
        let began = CGBeginDisplayConfiguration(&config)
        guard began == .success, let config else {
            return .failure(.modeApplyFailed(began.rawValue))
        }
        let configured = CGConfigureDisplayWithDisplayMode(config, displayID, mode, nil)
        if configured != .success {
            CGCancelDisplayConfiguration(config)
            return .failure(.modeApplyFailed(configured.rawValue))
        }
        let completed = CGCompleteDisplayConfiguration(config, .forSession)
        if completed != .success {
            return .failure(.modeApplyFailed(completed.rawValue))
        }
        return .success(())
    }

    private static func cgModes(for displayID: CGDirectDisplayID) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        guard let raw = CGDisplayCopyAllDisplayModes(displayID, options) else {
            return []
        }
        let array = raw as NSArray
        var modes: [CGDisplayMode] = []
        modes.reserveCapacity(array.count)
        for index in 0..<array.count {
            modes.append(array[index] as CGDisplayMode)
        }
        return modes
    }

    private static func summary(of mode: CGDisplayMode) -> DisplayModeSummary {
        DisplayModeSummary(
            width: mode.width,
            height: mode.height,
            pixelWidth: mode.pixelWidth,
            pixelHeight: mode.pixelHeight,
            refreshRate: mode.refreshRate
        )
    }
}
