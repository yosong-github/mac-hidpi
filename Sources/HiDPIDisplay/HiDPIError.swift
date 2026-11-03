import Foundation

public enum HiDPIError: Error, Equatable, CustomStringConvertible {
    case apiUnavailable
    case notEligible
    case noPresets
    case creationFailed(String)
    case didNotComeOnline(UInt32)
    case modeNotFound(requested: String, available: String)
    case mirrorFailed(Int32)
    case modeApplyFailed(Int32)

    public var description: String {
        switch self {
        case .apiUnavailable:
            return "这台系统的 CoreGraphics 没有 CGVirtualDisplay，无法创建虚拟显示器。"
        case .notEligible:
            return "这块屏幕不能开启 HiDPI（内建显示器，或不是独立的外接屏）。"
        case .noPresets:
            return "没法为这块屏幕算出可用的 HiDPI 分辨率。"
        case let .creationFailed(message):
            return "创建虚拟显示器失败：\(message)"
        case let .didNotComeOnline(displayID):
            return "虚拟显示器 \(displayID) 没有变为在线。"
        case let .modeNotFound(requested, available):
            return "没有找到 \(requested) 的 2× HiDPI 模式。系统返回的模式：\(available)"
        case let .mirrorFailed(code):
            return "把外接屏镜像到虚拟显示器失败（CGError \(code)）。"
        case let .modeApplyFailed(code):
            return "切换虚拟显示器分辨率失败（CGError \(code)）。"
        }
    }
}
