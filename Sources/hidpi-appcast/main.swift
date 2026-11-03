import Foundation
import HiDPICore

enum AppcastCLI {
    static func main() -> Int32 {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let options = Options(arguments) else {
            FileHandle.standardError.write(Data(usage.utf8))
            return 1
        }
        guard let version = ReleaseVersion.parse(options.version) else {
            FileHandle.standardError.write(Data("version must look like 1.2.3\n".utf8))
            return 1
        }
        let signature = options.signature?.trimmingCharacters(in: .whitespacesAndNewlines)
        let release = AppcastRelease(
            version: version,
            title: options.title ?? "HiDPI \(version)",
            notesHTML: options.notes ?? "<p>HiDPI \(version)</p>",
            feedURL: options.feedURL,
            enclosureURL: options.enclosureURL,
            length: options.length,
            edSignature: signature?.isEmpty == true ? nil : signature,
            pubDate: Date()
        )
        let xml = Appcast.xml(for: release)
        do {
            try xml.write(to: URL(fileURLWithPath: options.output), atomically: true, encoding: .utf8)
        } catch {
            FileHandle.standardError.write(Data("write failed: \(error.localizedDescription)\n".utf8))
            return 2
        }
        return 0
    }

    private static let usage = """
    usage: hidpi-appcast --version 1.2.3 --feed-url URL --enclosure-url URL \\
      --length BYTES --output appcast.xml [--signature ED25519] [--title TEXT] [--notes HTML]

    """
}

private struct Options {
    var version = ""
    var feedURL = ""
    var enclosureURL = ""
    var length = 0
    var output = ""
    var signature: String?
    var title: String?
    var notes: String?

    init?(_ arguments: [String]) {
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            index += 1
            guard index < arguments.count else {
                return nil
            }
            let value = arguments[index]
            index += 1
            switch flag {
            case "--version":
                version = value
            case "--feed-url":
                feedURL = value
            case "--enclosure-url":
                enclosureURL = value
            case "--length":
                guard let parsed = Int(value), parsed >= 0 else {
                    return nil
                }
                length = parsed
            case "--output":
                output = value
            case "--signature":
                signature = value
            case "--title":
                title = value
            case "--notes":
                notes = value
            default:
                return nil
            }
        }
        if version.isEmpty || feedURL.isEmpty || enclosureURL.isEmpty || output.isEmpty {
            return nil
        }
    }
}

exit(AppcastCLI.main())
