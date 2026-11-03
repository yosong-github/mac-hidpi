import Darwin
import Foundation

/// Asks WindowServer to rescan displays after an override is written.
/// BetterDisplay calls the private `SLSDetectDisplays`. Missing the symbol is not fatal;
/// the panel may still need to be reconnected before the new mode appears.
enum DisplayProbe {
    static func rescan() {
        let candidates = [
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
        ]
        for path in candidates {
            guard let handle = dlopen(path, RTLD_LAZY) else {
                continue
            }
            defer { dlclose(handle) }
            guard let symbol = dlsym(handle, "SLSDetectDisplays") else {
                continue
            }
            typealias Function = @convention(c) () -> Int32
            let function = unsafeBitCast(symbol, to: Function.self)
            _ = function()
            return
        }
    }
}
