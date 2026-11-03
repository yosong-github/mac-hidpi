import CGVirtualDisplayShim
import Foundation
import HiDPICore

enum VirtualDisplayClient {
    static func create(_ spec: VirtualDisplaySpec) throws -> HDVirtualDisplay {
        if !HDVirtualDisplay.isAPIAvailable() {
            throw HiDPIError.apiUnavailable
        }
        let modes: [[String: NSNumber]] = spec.modes.map { mode in
            [
                HDVirtualModeWidthKey: NSNumber(value: mode.width),
                HDVirtualModeHeightKey: NSNumber(value: mode.height),
                HDVirtualModeRefreshKey: NSNumber(value: mode.refreshRate),
            ]
        }
        var error: NSError?
        guard
            let display =
                HDVirtualDisplay(
                    name: spec.name,
                    maxPixelsWide: u32(spec.maxPixelsWide),
                    maxPixelsHigh: u32(spec.maxPixelsHigh),
                    widthMillimeters: spec.widthMillimeters,
                    heightMillimeters: spec.heightMillimeters,
                    vendorID: spec.vendorID,
                    productID: spec.productID,
                    serialNum: spec.serialNumber,
                    hiDPI: spec.hiDPI,
                    modes: modes,
                    error: &error
                )
        else {
            // HDVirtualDisplayErrorAPIUnavailable == 1. Compare the code so a Swift
            // rename of the imported enum cannot hide "API missing".
            if error?.domain == HDVirtualDisplayErrorDomain && error?.code == 1 {
                throw HiDPIError.apiUnavailable
            }
            throw HiDPIError.creationFailed(error?.localizedDescription ?? "unknown")
        }
        return display
    }

    private static func u32(_ value: Int) -> UInt32 {
        guard value > 0 else {
            return 0
        }
        if value > Int(UInt32.max) {
            return UInt32.max
        }
        return UInt32(value)
    }
}
