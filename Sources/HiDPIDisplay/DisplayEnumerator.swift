import AppKit
import CoreGraphics
import Foundation
import HiDPICore

public enum DisplayEnumerator {
    public static func snapshots() -> [DisplaySnapshot] {
        var count: UInt32 = 0
        let countResult = CGGetOnlineDisplayList(0, nil, &count)
        guard countResult == .success, count > 0 else {
            return []
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        let listResult = CGGetOnlineDisplayList(count, &ids, &count)
        guard listResult == .success else {
            return []
        }
        let listed = ids.prefix(Int(count))
        let snapshots = listed.map(snapshot(for:))
        return snapshots.sorted { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn {
                return !lhs.isBuiltIn
            }
            if lhs.frameMinX != rhs.frameMinX {
                return lhs.frameMinX < rhs.frameMinX
            }
            return lhs.displayID < rhs.displayID
        }
    }

    static func snapshot(for displayID: CGDirectDisplayID) -> DisplaySnapshot {
        let pixelWidth = Int(CGDisplayPixelsWide(displayID))
        let pixelHeight = Int(CGDisplayPixelsHigh(displayID))
        let panel = PanelPixels(width: pixelWidth, height: pixelHeight)
        let key = DisplayKey(
            vendorID: CGDisplayVendorNumber(displayID),
            productID: CGDisplayModelNumber(displayID),
            serialNumber: CGDisplaySerialNumber(displayID),
            unitNumber: CGDisplayUnitNumber(displayID)
        )
        let name = screenName(for: displayID)
        let ours = key.vendorID == ResolutionPlan.virtualVendorID || name.hasPrefix("HiDPI ")
        let builtIn = CGDisplayIsBuiltin(displayID) != 0
        let presets = ours || builtIn ? [] : ResolutionPlan.presets(for: panel)
        let bounds = CGDisplayBounds(displayID)
        return DisplaySnapshot(
            displayID: displayID,
            key: key,
            name: name,
            panel: panel,
            refreshRate: currentRefresh(displayID),
            frameMinX: bounds.origin.x,
            isBuiltIn: builtIn,
            isOurs: ours,
            presets: presets,
            defaultMode: ResolutionPlan.defaultPreset(for: panel, presets: presets)
        )
    }

    static func screenName(for displayID: CGDirectDisplayID) -> String {
        for screen in NSScreen.screens {
            let screenNumber = NSDeviceDescriptionKey(rawValue: "NSScreenNumber")
            guard let number = screen.deviceDescription[screenNumber] as? NSNumber else {
                continue
            }
            if number.uint32Value == displayID {
                let name = screen.localizedName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    return name
                }
            }
        }
        return "显示器 \(displayID)"
    }

    static func currentRefresh(_ displayID: CGDirectDisplayID) -> Double {
        guard let mode = CGDisplayCopyDisplayMode(displayID) else {
            return 60
        }
        return CGDisplayModeGetRefreshRate(mode)
    }
}
