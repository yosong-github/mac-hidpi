import Foundation

public struct PersistedSession: Equatable, Hashable, Codable, Sendable {
    public var key: DisplayKey
    public var logicalWidth: Int
    public var logicalHeight: Int

    public init(key: DisplayKey, logicalWidth: Int, logicalHeight: Int) {
        self.key = key
        self.logicalWidth = logicalWidth
        self.logicalHeight = logicalHeight
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
