import Foundation

public struct AppcastRelease: Equatable, Sendable {
    public var version: String
    public var title: String
    public var notesHTML: String
    public var minimumSystemVersion: String
    public var feedURL: String
    public var enclosureURL: String
    public var length: Int
    public var edSignature: String?
    public var pubDate: Date

    public init(
        version: String,
        title: String,
        notesHTML: String,
        minimumSystemVersion: String = "13.0.0",
        feedURL: String,
        enclosureURL: String,
        length: Int,
        edSignature: String?,
        pubDate: Date
    ) {
        self.version = version
        self.title = title
        self.notesHTML = notesHTML
        self.minimumSystemVersion = minimumSystemVersion
        self.feedURL = feedURL
        self.enclosureURL = enclosureURL
        self.length = length
        self.edSignature = edSignature
        self.pubDate = pubDate
    }
}

public enum Appcast {
    public static func xml(for release: AppcastRelease) -> String {
        let signature = release.edSignature?.trimmingCharacters(in: .whitespacesAndNewlines)
        let signatureAttribute: String
        if let signature, !signature.isEmpty {
            signatureAttribute = " sparkle:edSignature=\"\(escapeAttribute(signature))\""
        } else {
            signatureAttribute = ""
        }
        let date = rfc822(release.pubDate)
        let enclosure = "<enclosure url=\"\(escapeAttribute(release.enclosureURL))\" "
            + "length=\"\(release.length)\" type=\"application/octet-stream\"\(signatureAttribute)/>"
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <title>HiDPI</title>
            <link>\(escapeText(release.feedURL))</link>
            <description>HiDPI updates</description>
            <language>zh-CN</language>
            <item>
              <title>\(escapeText(release.title))</title>
              <pubDate>\(date)</pubDate>
              <sparkle:version>\(escapeText(release.version))</sparkle:version>
              <sparkle:shortVersionString>\(escapeText(release.version))</sparkle:shortVersionString>
              <sparkle:minimumSystemVersion>\(escapeText(release.minimumSystemVersion))</sparkle:minimumSystemVersion>
              <description><![CDATA[\(cdata(release.notesHTML))]]></description>
              \(enclosure)
            </item>
          </channel>
        </rss>
        """
    }

    static func rfc822(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.string(from: date)
    }

    static func escapeText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func escapeAttribute(_ value: String) -> String {
        escapeText(value)
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func cdata(_ value: String) -> String {
        value.replacingOccurrences(of: "]]>", with: "]]]]><![CDATA[>")
    }
}
