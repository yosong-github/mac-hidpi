import Foundation

public struct PersistedSession: Equatable, Hashable, Codable, Sendable {
    public var key: DisplayKey
    public var logicalWidth: Int
    public var logicalHeight: Int
    /// Set when the user picked a scale from the optional submenu.
    /// Older saves omit this and are not restored unless they already match native size.
    public var explicitScale: Bool

    public init(key: DisplayKey, logicalWidth: Int, logicalHeight: Int, explicitScale: Bool = false) {
        self.key = key
        self.logicalWidth = logicalWidth
        self.logicalHeight = logicalHeight
        self.explicitScale = explicitScale
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case logicalWidth
        case logicalHeight
        case explicitScale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(DisplayKey.self, forKey: .key)
        logicalWidth = try container.decode(Int.self, forKey: .logicalWidth)
        logicalHeight = try container.decode(Int.self, forKey: .logicalHeight)
        explicitScale = try container.decodeIfPresent(Bool.self, forKey: .explicitScale) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(logicalWidth, forKey: .logicalWidth)
        try container.encode(logicalHeight, forKey: .logicalHeight)
        try container.encode(explicitScale, forKey: .explicitScale)
    }

    /// Native looks-like sessions always come back. A non-native size comes back only
    /// when the user chose it. Saves from the old 1920×1080 default are skipped.
    public func modeToRestore(panel: PanelPixels, presets: [ScaledMode]) -> ScaledMode? {
        guard
            let mode = ResolutionPlan.resolveSavedMode(
                logicalWidth: logicalWidth,
                logicalHeight: logicalHeight,
                presets: presets
            )
        else {
            return nil
        }
        if explicitScale || ResolutionPlan.isNativeLooksLike(mode, on: panel) {
            return mode
        }
        return nil
    }
}

public struct PersistedState: Equatable, Codable, Sendable {
    public var sessions: [PersistedSession]

    public init(sessions: [PersistedSession] = []) {
        self.sessions = sessions
    }

    public func upsert(_ session: PersistedSession) -> PersistedState {
        var copy = self
        copy.sessions.removeAll { $0.key == session.key }
        copy.sessions.append(session)
        return copy
    }

    public func remove(_ key: DisplayKey) -> PersistedState {
        var copy = self
        copy.sessions.removeAll { $0.key == key }
        return copy
    }

    public func encode() -> Data? {
        try? JSONEncoder().encode(self)
    }

    public static func decode(from data: Data) -> PersistedState {
        (try? JSONDecoder().decode(PersistedState.self, from: data)) ?? PersistedState()
    }
}
