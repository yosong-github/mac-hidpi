import CoreGraphics
import Foundation

enum MirrorController {
    /// The physical display shows whatever the virtual display is rendering.
    static func mirror(source: CGDirectDisplayID, onto target: CGDirectDisplayID) -> Int32 {
        guard source != target else {
            return CGError.failure.rawValue
        }
        var config: CGDisplayConfigRef?
        let began = CGBeginDisplayConfiguration(&config)
        guard began == .success, let config else {
            return began.rawValue
        }
        let bounds = CGDisplayBounds(target)
        // Park the virtual desktop on the panel so the menu bar does not jump to a new origin.
        _ = CGConfigureDisplayOrigin(config, source, Int32(bounds.origin.x.rounded()), Int32(bounds.origin.y.rounded()))
        let mirrored = CGConfigureDisplayMirrorOfDisplay(config, target, source)
        if mirrored != .success {
            CGCancelDisplayConfiguration(config)
            return mirrored.rawValue
        }
        let completed = CGCompleteDisplayConfiguration(config, .forSession)
        return completed.rawValue
    }

    static func stopMirroring(_ target: CGDirectDisplayID) -> Int32 {
        let master = CGDisplayMirrorsDisplay(target)
        if master == 0 || master == target {
            return CGError.success.rawValue
        }
        var config: CGDisplayConfigRef?
        let began = CGBeginDisplayConfiguration(&config)
        guard began == .success, let config else {
            return began.rawValue
        }
        let cleared = CGConfigureDisplayMirrorOfDisplay(config, target, kCGNullDirectDisplay)
        if cleared != .success {
            CGCancelDisplayConfiguration(config)
            return cleared.rawValue
        }
        let completed = CGCompleteDisplayConfiguration(config, .forSession)
        return completed.rawValue
    }
}
