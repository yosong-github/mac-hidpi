import Foundation
import HiDPICore

public struct HiDPIActivation: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case realDisplay
        case virtualScreen
    }

    public var source: Source
    public var summary: DisplayModeSummary
    public var note: String?

    public init(source: Source, summary: DisplayModeSummary, note: String? = nil) {
        self.source = source
        self.summary = summary
        self.note = note
    }
}

/// Turns HiDPI on for one panel. The real display is preferred: install a scale-resolution
/// override if needed, then switch that panel's own mode. A virtual screen is only used
/// when the real mode is still missing, so the desktop can become sharp before a reconnect.
@MainActor
public final class HiDPICoordinator {
    private let engine = HiDPIEngine()
    private var realModes: [DisplayKey: DisplayModeSummary] = [:]
    private var notes: [DisplayKey: String] = [:]

    public init() {}

    public func activation(for key: DisplayKey) -> HiDPIActivation? {
        if let summary = realModes[key] {
            return HiDPIActivation(source: .realDisplay, summary: summary, note: notes[key])
        }
        if let summary = engine.appliedSummary(for: key) {
            return HiDPIActivation(source: .virtualScreen, summary: summary, note: notes[key])
        }
        return nil
    }

    public func capturedPanel(for key: DisplayKey) -> PanelPixels? {
        engine.capturedPanel(for: key)
    }

    public func isActive(_ key: DisplayKey) -> Bool {
        activation(for: key) != nil
    }

    public func enable(_ display: DisplaySnapshot) async throws {
        disableVirtual(display)
        if let summary = switchReal(display, hiDPI: true) {
            realModes[display.key] = summary
            notes[display.key] = nil
            return
        }
        let plist = try DisplayOverrideDocument.propertyList(
            vendorID: display.key.vendorID,
            productID: display.key.productID,
            name: display.name,
            panel: display.panel,
            modes: display.presets
        )
        do {
            try OverrideInstaller.install(
                data: plist,
                vendorID: display.key.vendorID,
                productID: display.key.productID
            )
        } catch let error as OverrideInstallerError where error == .cancelled {
            try await useVirtual(
                display,
                note: "未写入覆盖文件。当前用虚拟屏幕让整个桌面按 2× 绘制。"
            )
            return
        }
        DisplayProbe.rescan()
        if let summary = switchReal(display, hiDPI: true) {
            realModes[display.key] = summary
            notes[display.key] = nil
            return
        }
        try await useVirtual(
            display,
            note: "覆盖已写入。重新插拔显示器或注销后，再打开开关就会改用真实屏幕。当前先用虚拟屏幕。"
        )
    }

    public func disable(_ display: DisplaySnapshot) {
        disableVirtual(display)
        realModes[display.key] = nil
        notes[display.key] = nil
        _ = RealDisplayModeSwitcher.applyLowDPI(displayID: display.displayID, panel: display.panel)
    }

    public func shutdown(_ displays: [DisplaySnapshot]) {
        for display in displays where isActive(display.key) {
            disable(display)
        }
        engine.disableAll()
        realModes.removeAll()
        notes.removeAll()
    }

    public func removeOverrides(_ display: DisplaySnapshot) throws {
        disable(display)
        try OverrideInstaller.remove(vendorID: display.key.vendorID, productID: display.key.productID)
        DisplayProbe.rescan()
    }

    public func select(_ display: DisplaySnapshot, mode: ScaledMode) async throws {
        // Optional scaled sizes. Native stays on the real display when that mode exists.
        if ResolutionPlan.isNativeLooksLike(mode, on: display.panel),
            let summary = switchReal(display, hiDPI: true)
        {
            disableVirtual(display)
            realModes[display.key] = summary
            notes[display.key] = nil
            return
        }
        disable(display)
        try await engine.enable(display: display, mode: mode)
        notes[display.key] = "这一档改变了看起来像的尺寸，并用虚拟屏幕绘制。"
    }

    private func switchReal(_ display: DisplaySnapshot, hiDPI: Bool) -> DisplayModeSummary? {
        let result =
            hiDPI
            ? RealDisplayModeSwitcher.applyHiDPI(displayID: display.displayID, panel: display.panel)
            : RealDisplayModeSwitcher.applyLowDPI(displayID: display.displayID, panel: display.panel)
        guard case let .success(summary) = result else {
            return nil
        }
        return summary
    }

    private func disableVirtual(_ display: DisplaySnapshot) {
        engine.disable(key: display.key)
    }

    private func useVirtual(_ display: DisplaySnapshot, note: String) async throws {
        guard let mode = display.defaultMode else {
            throw HiDPIError.noPresets
        }
        try await engine.enable(display: display, mode: mode)
        realModes[display.key] = nil
        notes[display.key] = note
    }
}
