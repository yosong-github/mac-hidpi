import AppKit
import Foundation
import HiDPICore
import HiDPIDisplay
import Sparkle

struct MenuDisplay: Identifiable, Equatable {
    var snapshot: DisplaySnapshot
    var isEnabled: Bool
    var activeMode: ScaledMode?

    var id: String {
        snapshot.id
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var displays: [MenuDisplay] = []
    @Published private(set) var isBusy = false
    @Published var lastError: String?

    private let engine = HiDPIEngine()
    private let store = SessionStore()
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
        engine.disableAll()
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
            let mode = display.activeMode ?? display.snapshot.defaultMode
            guard let mode else {
                lastError = HiDPIError.noPresets.description
                return
            }
            run {
                try await self.engine.enable(
                    display: display.snapshot,
                    mode: mode
                )
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
            engine.disable(key: display.snapshot.key)
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
            try await self.engine.enable(
                display: display.snapshot,
                mode: mode
            )
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
    }

    func modeLabel(_ mode: ScaledMode, on snapshot: DisplaySnapshot) -> String {
        var label = "\(mode.logicalWidth)×\(mode.logicalHeight)"
        if mode == snapshot.defaultMode {
            label += " · 推荐"
        }
        if mode.isPixelAligned(with: snapshot.panel) {
            label += " · 像素对齐"
        }
        return label
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
            if engine.isActive(session.key) {
                continue
            }
            guard
                let display = displays.first(where: { item in
                    item.snapshot.key == session.key && item.snapshot.isEligible
                })
            else {
                continue
            }
            let mode =
                ResolutionPlan.resolveSavedMode(
                    logicalWidth: session.logicalWidth,
                    logicalHeight: session.logicalHeight,
                    presets: display.snapshot.presets
                ) ?? display.snapshot.defaultMode
            guard let mode else {
                continue
            }
            do {
                try await engine.enable(display: display.snapshot, mode: mode)
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
        engine.dropDisconnected(online: snapshots.map(\.key))
        displays = snapshots.map { snapshot in
            MenuDisplay(
                snapshot: snapshot,
                isEnabled: engine.isActive(snapshot.key),
                activeMode: engine.activeMode(for: snapshot.key)
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
