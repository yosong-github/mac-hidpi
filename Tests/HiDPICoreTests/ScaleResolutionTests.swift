import HiDPICore
import XCTest

final class ScaleResolutionTests: XCTestCase {
    func testHiDPIEntryMatchesOneKeyHiDPITwelveByteForm() {
        let data = ScaleResolutionCodec.encode(.hiDPI(pixelWidth: 5120, pixelHeight: 2880))
        XCTAssertEqual(data.count, 12)
        XCTAssertEqual(data.base64EncodedString(), "AAAUAAAAC0AAAAAB")
        XCTAssertEqual(
            ScaleResolutionCodec.decode(data),
            .hiDPI(pixelWidth: 5120, pixelHeight: 2880)
        )
    }

    func testScaled1080pHiDPIEntry() {
        let data = ScaleResolutionCodec.encode(.hiDPI(pixelWidth: 3840, pixelHeight: 2160))
        XCTAssertEqual(data.base64EncodedString(), "AAAPAAAACHAAAAAB")
    }

    func testLowDPIRoundTripIsEightBytes() {
        let data = ScaleResolutionCodec.encode(.lowDPI(width: 2560, height: 1440))
        XCTAssertEqual(data.count, 8)
        XCTAssertEqual(data.base64EncodedString(), "AAAKAAAABaA=")
        XCTAssertEqual(ScaleResolutionCodec.decode(data), .lowDPI(width: 2560, height: 1440))
    }

    func testNativeModeProducesLowAndHighVariants() {
        let entries = ScaleResolutionCodec.entries(
            for: ScaledMode(logicalWidth: 2560, logicalHeight: 1440, scale: 2)
        )
        XCTAssertEqual(
            entries,
            [
                .lowDPI(width: 2560, height: 1440),
                .hiDPI(pixelWidth: 5120, pixelHeight: 2880),
                .lowDPI(width: 5120, height: 2880),
            ]
        )
    }

    func testOverridePlistCarriesNativeHiDPIAndMarker() throws {
        let panel = PanelPixels(width: 2560, height: 1440)
        let modes = ResolutionPlan.presets(for: panel)
        let data = try DisplayOverrideDocument.propertyList(
            vendorID: 0x10AC,
            productID: 0xD06E,
            name: "DELL U2722D",
            panel: panel,
            modes: modes
        )
        let root = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        XCTAssertEqual(root["DisplayVendorID"] as? Int, 0x10AC)
        XCTAssertEqual(root["DisplayProductID"] as? Int, 0xD06E)
        XCTAssertEqual(root["DisplayProductName"] as? String, "DELL U2722D")
        XCTAssertEqual(root[DisplayOverrideDocument.markerKey] as? Bool, true)
        let scales = try XCTUnwrap(root["scale-resolutions"] as? [Data])
        let native = ScaleResolutionCodec.encode(.hiDPI(pixelWidth: 5120, pixelHeight: 2880))
        XCTAssertTrue(scales.contains(native))
        XCTAssertEqual(root["default-resolution"] as? Data, native)
        let panelData = try XCTUnwrap(root["DisplayPixelDimensions"] as? Data)
        XCTAssertEqual(
            ScaleResolutionCodec.decode(panelData),
            .lowDPI(width: 2560, height: 1440)
        )
        XCTAssertTrue(DisplayOverrideDocument.containsMarker(data))
    }
}

final class OverrideLocationTests: XCTestCase {
    func testPathStaysInsideOverridesRoot() {
        let path = OverrideLocation.propertyListPath(vendorID: 0x10AC, productID: 0xD06E)
        XCTAssertEqual(
            path,
            "/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-10ac/DisplayProductID-d06e"
        )
        XCTAssertTrue(OverrideLocation.isAllowed(path))
        XCTAssertTrue(OverrideLocation.isAllowed(OverrideLocation.backupPath(vendorID: 0x10AC, productID: 0xD06E)))
        XCTAssertFalse(OverrideLocation.isAllowed("/Library/Displays/../etc/passwd"))
        XCTAssertFalse(OverrideLocation.isAllowed("/tmp/DisplayProductID-1"))
    }

    func testInstallCommandEnablesWindowServerAndRejectsEscape() {
        let command = OverrideInstallScript.installCommand(
            vendorID: 0x10AC,
            productID: 0xD06E,
            sourcePlist: "/tmp/hidpi-test.plist"
        )
        XCTAssertNotNil(command)
        XCTAssertTrue(command?.contains("DisplayResolutionEnabled -bool YES") == true)
        XCTAssertTrue(command?.contains("DisplayVendorID-10ac/DisplayProductID-d06e") == true)
        XCTAssertNil(
            OverrideInstallScript.installCommand(
                vendorID: 0x10AC,
                productID: 0xD06E,
                sourcePlist: "/tmp/../etc/passwd"
            )
        )
    }

    func testRemoveCommandRestoresBackup() {
        let command = OverrideInstallScript.removeCommand(vendorID: 0x10AC, productID: 0xD06E)
        XCTAssertTrue(command?.contains("hidpi-backup") == true)
        XCTAssertTrue(command?.contains("rm -f") == true)
    }
}

final class HiDPIVariantPickerTests: XCTestCase {
    func testToggleKeeps2560LooksLikeAndFlipsBackingScale() {
        let panel = PanelPixels(width: 2560, height: 1440)
        let modes = [
            DisplayModeSummary(width: 2560, height: 1440, pixelWidth: 2560, pixelHeight: 1440, refreshRate: 60),
            DisplayModeSummary(width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60),
            DisplayModeSummary(width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 60),
        ]
        let on = HiDPIVariantPicker.hiDPIMode(panel: panel, among: modes)
        let off = HiDPIVariantPicker.lowDPIMode(panel: panel, among: modes)
        XCTAssertEqual(on?.width, 2560)
        XCTAssertEqual(on?.pixelWidth, 5120)
        XCTAssertEqual(on?.pixelHeight, 2880)
        XCTAssertEqual(off?.width, 2560)
        XCTAssertEqual(off?.pixelWidth, 2560)
        XCTAssertEqual(off?.pixelHeight, 1440)
    }
}
