import Foundation

public enum ReleaseVersion {
    /// Accepts `1.2.3` or `v1.2.3`. Rejects pre-release suffixes and leading zeros.
    public static func parse(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") {
            text.removeFirst()
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            return nil
        }
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isNumber) else {
                return nil
            }
            if part.count > 1, part.first == "0" {
                return nil
            }
        }
        return text
    }
}
