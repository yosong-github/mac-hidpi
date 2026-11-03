import AppKit
import Foundation
import HiDPICore
import HiDPIDisplay
import Sparkle

struct MenuDisplay: Identifiable, Equatable {
    var snapshot: DisplaySnapshot
    var isEnabled: Bool
    var activeMode: ScaledMode?
    /// Mode read back after HiDPI was applied, on the real panel or the virtual screen.
    var applied: DisplayModeSummary?
    var sourceNote: String?

    var id: String {
        snapshot.id
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var displays: [MenuDisplay] = []
    @Published private(set) var isBusy = false
    @Published var lastError: String?

    private let coordinator = HiDPICoordinator()
    private let store = SessionStore()
    private var knownPanels: [DisplayKey: PanelPixels] = [:]
    private var observer: NSObjectProtocol?
    private var refreshTask: Task<Void, Never>?
    private var updater: SPUStandardUpdaterController?

    var isAnyEnabled: Bool {
        displays.contains { $0.isEnabled }
    }

    var versionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return short ?? ""
    }

    func attach(updater: SPUStandardUpdaterController?) {
        self.updater = updater
    }

    func start() {
        DisplayObserver.start()
        observer = NotificationCenter.default.addObserver(
            forName: DisplayObserver.changed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleRefresh()
            }
        }
        scheduleRefresh()
    }

    func shutdown() {
        refreshTask?.cancel()
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        DisplayObserver.stop()
        coordinator.shutdown(displays.map(\.snapshot))
    }

    func checkForUpdates() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        updater?.checkForUpdates(nil)
    }

    func setEnabled(_ display: MenuDisplay, _ enabled: Bool) {
        guard !isBusy else {
            return
        }
        if enabled {
            // The toggle always keeps the native looks-like size. Scaled sizes are opt-in.
            let mode = display.snapshot.defaultMode
            guard let mode else {
                lastError = HiDPIError.noPresets.description
                return
            }
            run {
                try await self.coordinator.enable(display.snapshot)
                self.store.save(
                    self.store.load().upsert(
                        PersistedSession(
                            key: display.snapshot.key,
                            logicalWidth: mode.logicalWidth,
                            logicalHeight: mode.logicalHeight
                        )
                    )
                )
            }
        } else {
            coordinator.disable(display.snapshot)
            store.save(store.load().remove(display.snapshot.key))
            lastError = nil
            reload()
        }
    }

    func select(_ display: MenuDisplay, mode: ScaledMode) {
        guard !isBusy, display.snapshot.isEligible else {
            return
        }
        run {
            try await self.coordinator.select(display.snapshot, mode: mode)
            self.store.save(
                self.store.load().upsert(
                    PersistedSession(
                        key: display.snapshot.key,
                        logicalWidth: mode.logicalWidth,
                        logicalHeight: mode.logicalHeight,
                        explicitScale: true
                    )
                )
            )
        }
    }

    func modeLabel(_ mode: ScaledMode, on snapshot: DisplaySnapshot) -> String {
        var label = "\(mode.logicalWidth) × \(mode.logicalHeight)"
        if ResolutionPlan.isNativeLooksLike(mode, on: snapshot.panel) {
            label += " · 原生"
        }
        if mode.isPixelAligned(with: snapshot.panel) {
            label += " · 像素对齐"
        }
        return label
    }

    /// Looks-like size, matching BetterDisplay's「分辨率 2560 × 1440」. The toggle must not change it.
    func resolutionLine(_ display: MenuDisplay) -> String {
        if display.isEnabled, let applied = display.applied {
            return "分辨率 \(applied.width) × \(applied.height)"
        }
        if let active = display.activeMode {
            return "分辨率 \(active.logicalWidth) × \(active.logicalHeight)"
        }
        if let current = display.snapshot.currentMode {
            return "分辨率 \(current.width) × \(current.height)"
        }
        let panel = display.snapshot.panel
        return "分辨率 \(panel.width) × \(panel.height)"
    }

    /// Whole-desktop backing scale. 2× means every window is drawn at twice the pixels, not just text.
    func diagnosticLine(_ display: MenuDisplay) -> String? {
        if let applied = display.applied {
            return backingLine(applied, note: display.sourceNote)
        }
        if let current = display.snapshot.currentMode {
            return backingLine(current, note: nil)
        }
        return nil
    }

    private func backingLine(_ mode: DisplayModeSummary, note: String?) -> String {
        let scale: String
        if mode.pixelWidth == mode.width * 2 && mode.pixelHeight == mode.height * 2 {
            scale = "2×"
        } else if mode.pixelWidth == mode.width && mode.pixelHeight == mode.height {
            scale = "1×"
        } else {
            scale = "非整数"
        }
        let points = "\(mode.width) × \(mode.height)"
        let pixels = "\(mode.pixelWidth) × \(mode.pixelHeight)"
        let source = note.map { "（\($0)）" } ?? ""
        return "整个桌面 \(scale)：\(points) 点，\(pixels) 像素\(source)"
    }

    func removeOverrides(_ display: MenuDisplay) {
        guard !isBusy else {
            return
        }
        run {
            try self.coordinator.removeOverrides(display.snapshot)
            self.store.save(self.store.load().remove(display.snapshot.key))
        }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else {
                return
            }
            let known = Set(self.displays.map(\.snapshot.key))
            self.reload()
            guard !self.isBusy else {
                return
            }
            let pending = self.store.load().sessions.filter { session in
                !known.contains(session.key)
                    && self.displays.contains { item in
                        item.snapshot.key == session.key && !item.isEnabled && item.snapshot.isEligible
                    }
            }
            guard !pending.isEmpty else {
                return
            }
            await self.restore(pending)
        }
    }

    private func restore(_ sessions: [PersistedSession]) async {
        isBusy = true
        defer {
            isBusy = false
            reload()
        }
        for session in sessions {
            if coordinator.isActive(session.key) {
                continue
            }
            guard
                let display = displays.first(where: { item in
                    item.snapshot.key == session.key && item.snapshot.isEligible
                })
            else {
                continue
            }
            guard
                let mode = session.modeToRestore(
                    panel: display.snapshot.panel,
                    presets: display.snapshot.presets
                )
            else {
                continue
            }
            do {
                try await coordinator.select(display.snapshot, mode: mode)
                lastError = nil
            } catch {
                lastError = (error as? HiDPIError)?.description ?? error.localizedDescription
            }
        }
    }

    private func run(_ body: @escaping () async throws -> Void) {
        isBusy = true
        Task { @MainActor in
            defer {
                self.isBusy = false
                self.reload()
            }
            do {
                try await body()
                self.lastError = nil
            } catch {
                self.lastError = (error as? HiDPIError)?.description ?? error.localizedDescription
            }
        }
    }

    private func reload() {
        let snapshots = DisplayEnumerator.snapshots()
        for snapshot in snapshots where snapshot.currentMode?.isHiDPI != true {
            knownPanels[snapshot.key] = snapshot.panel
        }
        displays = snapshots.map { snapshot in
            let remembered = knownPanels[snapshot.key] ?? coordinator.capturedPanel(for: snapshot.key)
            let locked = remembered.map { snapshot.locked(to: $0) } ?? snapshot
            let activation = coordinator.activation(for: snapshot.key)
            return MenuDisplay(
                snapshot: locked,
                isEnabled: activation != nil,
                activeMode: activation.map {
                    ScaledMode(logicalWidth: $0.summary.width, logicalHeight: $0.summary.height, scale: 2)
                },
                applied: activation?.summary,
                sourceNote: activation.map { item in
                    switch item.source {
                    case .realDisplay:
                        return item.note ?? "真实屏幕"
                    case .virtualScreen:
                        return item.note ?? "虚拟屏幕"
                    }
                }
            )
        }
    }
}

final class SessionStore {
    private let defaults: UserDefaults
    private let key = "enabledSessions"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PersistedState {
        guard let data = defaults.data(forKey: key) else {
            return PersistedState()
        }
        return PersistedState.decode(from: data)
    }

    func save(_ state: PersistedState) {
        guard let data = state.encode() else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
