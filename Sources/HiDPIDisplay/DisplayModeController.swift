import CoreGraphics
import Foundation
import HiDPICore

enum DisplayModeController {
    static func currentSummary(for displayID: CGDirectDisplayID) -> DisplayModeSummary? {
        guard let mode = CGDisplayCopyDisplayMode(displayID) else {
            return nil
        }
        return summary(of: mode)
    }

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

    static func applyExact(
        displayID: CGDirectDisplayID,
        width: Int,
        height: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        refreshRate: Double
    ) -> Result<Void, HiDPIError> {
        let pairs = cgModes(for: displayID).map { mode in
            (mode: mode, summary: summary(of: mode))
        }
        let matches = pairs.filter {
            $0.summary.width == width
                && $0.summary.height == height
                && $0.summary.pixelWidth == pixelWidth
                && $0.summary.pixelHeight == pixelHeight
        }
        guard let match = matches.min(by: { lhs, rhs in
            abs(lhs.summary.refreshRate - refreshRate) < abs(rhs.summary.refreshRate - refreshRate)
        }) else {
            return .failure(
                .modeNotFound(
                    requested: "\(width)x\(height) pixels \(pixelWidth)x\(pixelHeight)",
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
        // CGDisplayMode is a CF type. Bridging the array element with `as` / `as?`
        // is rejected by the current SDK, so read the pointers directly.
        let count = CFArrayGetCount(raw)
        var modes: [CGDisplayMode] = []
        modes.reserveCapacity(count)
        for index in 0..<count {
            guard let pointer = CFArrayGetValueAtIndex(raw, index) else {
                continue
            }
            let mode = Unmanaged<CGDisplayMode>.fromOpaque(pointer).takeUnretainedValue()
            modes.append(mode)
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
