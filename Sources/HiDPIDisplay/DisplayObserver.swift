import CoreGraphics
import Foundation

public enum DisplayObserver {
    public static let changed = Notification.Name("com.yosong.mac-hidpi.displaysChanged")

    private static let callback: CGDisplayReconfigurationCallBack = { _, flags, _ in
        if flags.contains(.beginConfiguration) {
            return
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: DisplayObserver.changed, object: nil)
        }
    }

    public static func start() {
        CGDisplayRegisterReconfigurationCallback(callback, nil)
    }

    public static func stop() {
        CGDisplayRemoveReconfigurationCallback(callback, nil)
    }
}
