import Foundation

/// Paths under `/Library/Displays/.../Overrides`. The privileged writer refuses anything else.
public enum OverrideLocation {
    public static let root = "/Library/Displays/Contents/Resources/Overrides"
    public static let windowServerDomain = "/Library/Preferences/com.apple.windowserver"

    public static func vendorDirectory(vendorID: UInt32) -> String {
        "\(root)/DisplayVendorID-\(hex(vendorID))"
    }

    public static func propertyListPath(vendorID: UInt32, productID: UInt32) -> String {
        "\(vendorDirectory(vendorID: vendorID))/DisplayProductID-\(hex(productID))"
    }

    public static func backupPath(vendorID: UInt32, productID: UInt32) -> String {
        propertyListPath(vendorID: vendorID, productID: productID) + ".hidpi-backup"
    }

    /// True only for our own plist or its backup, after resolving `.` and `..`.
    public static func isAllowed(_ path: String) -> Bool {
        let rootURL = URL(fileURLWithPath: root, isDirectory: true).standardizedFileURL
        let candidate = URL(fileURLWithPath: path).standardizedFileURL
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        let candidatePath = candidate.path
        guard candidatePath.hasPrefix(rootPath) else {
            return false
        }
        let relative = String(candidatePath.dropFirst(rootPath.count))
        let parts = relative.split(separator: "/")
        guard parts.count == 2 else {
            return false
        }
        let vendor = parts[0]
        let product = parts[1]
        guard vendor.hasPrefix("DisplayVendorID-"), product.hasPrefix("DisplayProductID-") else {
            return false
        }
        let vendorHex = vendor.dropFirst("DisplayVendorID-".count)
        let productName = String(product)
        let productHex: Substring
        if productName.hasSuffix(".hidpi-backup") {
            productHex = product.dropFirst("DisplayProductID-".count).dropLast(".hidpi-backup".count)
        } else {
            productHex = product.dropFirst("DisplayProductID-".count)
        }
        return isHex(vendorHex) && isHex(productHex)
    }

    public static func hex(_ value: UInt32) -> String {
        String(value, radix: 16, uppercase: false)
    }

    private static func isHex(_ text: Substring) -> Bool {
        let digits = Set("0123456789abcdef")
        return !text.isEmpty && text.allSatisfy { digits.contains($0) }
    }
}

public enum OverrideInstallScript {
    /// Shell run as root. Returns nil when a path could escape the overrides directory.
    public static func installCommand(vendorID: UInt32, productID: UInt32, sourcePlist: String) -> String? {
        let destination = OverrideLocation.propertyListPath(vendorID: vendorID, productID: productID)
        let directory = OverrideLocation.vendorDirectory(vendorID: vendorID)
        let backup = OverrideLocation.backupPath(vendorID: vendorID, productID: productID)
        guard
            OverrideLocation.isAllowed(destination),
            OverrideLocation.isAllowed(backup),
            isSafeSource(sourcePlist)
        else {
            return nil
        }
        return """
        mkdir -p \(quote(directory)) && \
        if [ -f \(quote(destination)) ] && [ ! -f \(quote(backup)) ]; then \
        cp \(quote(destination)) \(quote(backup)); fi && \
        cp \(quote(sourcePlist)) \(quote(destination)) && \
        chown root:wheel \(quote(destination)) && \
        chmod 644 \(quote(destination)) && \
        /usr/bin/defaults write \(quote(OverrideLocation.windowServerDomain)) \
        DisplayResolutionEnabled -bool YES
        """
    }

    /// Removes only this app's plist. Restores the pre-existing file when we backed it up.
    public static func removeCommand(vendorID: UInt32, productID: UInt32) -> String? {
        let destination = OverrideLocation.propertyListPath(vendorID: vendorID, productID: productID)
        let directory = OverrideLocation.vendorDirectory(vendorID: vendorID)
        let backup = OverrideLocation.backupPath(vendorID: vendorID, productID: productID)
        guard OverrideLocation.isAllowed(destination), OverrideLocation.isAllowed(backup) else {
            return nil
        }
        return """
        if [ -f \(quote(backup)) ]; then \
        mv \(quote(backup)) \(quote(destination)); \
        else rm -f \(quote(destination)); fi; \
        rmdir \(quote(directory)) 2>/dev/null || true
        """
    }

    private static func isSafeSource(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.contains("'") && !path.contains("\n") && !path.contains("..")
    }

    private static func quote(_ path: String) -> String {
        "'" + path + "'"
    }
}
