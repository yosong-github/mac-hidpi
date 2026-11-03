import CGVirtualDisplayShim
import CoreGraphics
import Foundation
import HiDPICore
import os

/// Creates one HiDPI virtual display per enabled panel and mirrors the panel onto it.
/// The virtual display object must stay alive; quitting the app releases it.
/// Main actor: CGVirtualDisplay creation is documented to require the main thread.
@MainActor
public final class HiDPIEngine {
    private let log = Logger(subsystem: "com.yosong.mac-hidpi", category: "engine")
    private var sessions: [DisplayKey: ActiveSession] = [:]

    public init() {}

    public func isActive(_ key: DisplayKey) -> Bool {
        sessions[key] != nil
    }

    public func activeMode(for key: DisplayKey) -> ScaledMode? {
        sessions[key]?.mode
    }

    public func activeKeys() -> [DisplayKey] {
        Array(sessions.keys)
    }

    public func enable(display: DisplaySnapshot, mode: ScaledMode) async throws {
        guard display.isEligible else {
            throw HiDPIError.notEligible
        }
        disable(key: display.key)
        let refresh = ResolutionPlan.normalizedRefreshRate(display.refreshRate)
        let attempts = ResolutionPlan.attempts(
            displayName: display.name,
            panel: display.panel,
            mode: mode,
            refreshRate: refresh,
            identity: display.key
        )
        var available = ""
        var lastError: HiDPIError = .creationFailed("no attempt")
        for attempt in attempts {
            let virtual: HDVirtualDisplay
            do {
                virtual = try VirtualDisplayClient.create(attempt.spec)
            } catch let error as HiDPIError {
                if case .apiUnavailable = error {
                    throw error
                }
                lastError = error
                log.error("virtual display create failed (\(String(describing: attempt.kind))): \(error.description)")
                continue
            } catch {
                lastError = .creationFailed(error.localizedDescription)
                continue
            }

            let online = await waitUntilOnline(virtual.displayID)
            guard online else {
                lastError = .didNotComeOnline(virtual.displayID)
                continue
            }
            let matched = await waitForMatch(
                displayID: virtual.displayID,
                mode: mode,
                refreshRate: refresh
            )
            guard matched else {
                let modes = DisplayModeController.summaries(for: virtual.displayID)
                available = ModeMatching.describe(modes)
                log.error("no HiDPI mode after \(String(describing: attempt.kind)): \(available)")
                continue
            }

            _ = MirrorController.stopMirroring(display.displayID)
            let modeResult = DisplayModeController.applyBest(
                displayID: virtual.displayID,
                logicalWidth: mode.logicalWidth,
                logicalHeight: mode.logicalHeight,
                refreshRate: refresh
            )
            if case let .failure(error) = modeResult {
                lastError = error
                log.error("mode apply failed before mirror: \(error.description)")
            }
            let mirrorCode = MirrorController.mirror(source: virtual.displayID, onto: display.displayID)
            if mirrorCode != CGError.success.rawValue {
                _ = MirrorController.stopMirroring(display.displayID)
                lastError = .mirrorFailed(mirrorCode)
                log.error("mirror failed: \(mirrorCode)")
                continue
            }
            let afterMirror = DisplayModeController.applyBest(
                displayID: virtual.displayID,
                logicalWidth: mode.logicalWidth,
                logicalHeight: mode.logicalHeight,
                refreshRate: refresh
            )
            if case let .failure(error) = afterMirror {
                _ = MirrorController.stopMirroring(display.displayID)
                lastError = error
                log.error("mode apply failed after mirror: \(error.description)")
                continue
            }
            sessions[display.key] = ActiveSession(
                key: display.key,
                physicalID: display.displayID,
                virtual: virtual,
                mode: mode
            )
            let logical = "\(mode.logicalWidth)x\(mode.logicalHeight)"
            log.info(
                "HiDPI on display \(display.displayID) via virtual \(virtual.displayID) at \(logical)"
            )
            return
        }
        if case .mirrorFailed = lastError {
            throw lastError
        }
        if available.isEmpty {
            throw lastError
        }
        throw HiDPIError.modeNotFound(
            requested: "\(mode.logicalWidth)x\(mode.logicalHeight)",
            available: available
        )
    }

    public func disable(key: DisplayKey) {
        guard let session = sessions.removeValue(forKey: key) else {
            return
        }
        let code = MirrorController.stopMirroring(session.physicalID)
        if code != CGError.success.rawValue {
            log.error("stop mirror failed for \(session.physicalID): \(code)")
        }
        // `session` (and its virtual display) releases at the end of this scope.
        log.info("HiDPI off for \(session.physicalID)")
    }

    public func disableAll() {
        for key in Array(sessions.keys) {
            disable(key: key)
        }
    }

    public func dropDisconnected(online: [DisplayKey]) {
        let live = Set(online)
        for key in Array(sessions.keys) where !live.contains(key) {
            disable(key: key)
        }
    }

    private func waitUntilOnline(_ displayID: CGDirectDisplayID) async -> Bool {
        for _ in 0..<40 {
            if CGDisplayIsOnline(displayID) != 0 {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return CGDisplayIsOnline(displayID) != 0
    }

    private func waitForMatch(displayID: CGDirectDisplayID, mode: ScaledMode, refreshRate: Double) async -> Bool {
        for _ in 0..<40 {
            let modes = DisplayModeController.summaries(for: displayID)
            if ModeMatching.bestHiDPIMode(
                among: modes,
                logicalWidth: mode.logicalWidth,
                logicalHeight: mode.logicalHeight,
                refreshRate: refreshRate
            ) != nil {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }
}

private final class ActiveSession {
    let key: DisplayKey
    let physicalID: CGDirectDisplayID
    let virtual: HDVirtualDisplay
    let mode: ScaledMode

    init(key: DisplayKey, physicalID: CGDirectDisplayID, virtual: HDVirtualDisplay, mode: ScaledMode) {
        self.key = key
        self.physicalID = physicalID
        self.virtual = virtual
        self.mode = mode
    }
}
