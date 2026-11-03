import Foundation
import HiDPICore

enum OverrideInstallerError: Error, Equatable, CustomStringConvertible {
    case unsafePath
    case cancelled
    case failed(String)

    var description: String {
        switch self {
        case .unsafePath:
            return "覆盖文件路径不在 /Library/Displays 的 Overrides 目录里，已拒绝写入。"
        case .cancelled:
            return "已取消管理员授权，没有写入显示器覆盖。"
        case let .failed(message):
            return "写入显示器覆盖失败：\(message)"
        }
    }
}

/// Asks for an administrator password once, then writes only our override plist.
enum OverrideInstaller {
    static func install(data: Data, vendorID: UInt32, productID: UInt32) throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("hidpi-\(UUID().uuidString).plist")
        try data.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        guard
            let command =
                OverrideInstallScript.installCommand(
                    vendorID: vendorID,
                    productID: productID,
                    sourcePlist: source.path
                )
        else {
            throw OverrideInstallerError.unsafePath
        }
        try AdminShell.run(command)
    }

    static func remove(vendorID: UInt32, productID: UInt32) throws {
        guard
            let command =
                OverrideInstallScript.removeCommand(
                    vendorID: vendorID,
                    productID: productID
                )
        else {
            throw OverrideInstallerError.unsafePath
        }
        try AdminShell.run(command)
    }
}

enum AdminShell {
    static func run(_ command: String) throws {
        let script = "do shell script " + appleQuote(command) + " with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            if text.localizedCaseInsensitiveContains("cancel")
                || text.localizedCaseInsensitiveContains("取消")
            {
                throw OverrideInstallerError.cancelled
            }
            throw OverrideInstallerError.failed(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func appleQuote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
