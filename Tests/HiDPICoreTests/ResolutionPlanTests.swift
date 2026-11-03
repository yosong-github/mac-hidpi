import HiDPICore
import XCTest

final class ResolutionPlanTests: XCTestCase {
    func test1440pLadderMatchesRequestedHiDPISizes() {
        let panel = PanelPixels(width: 2560, height: 1440)
        let presets = ResolutionPlan.presets(for: panel)
        let logical = presets.map { ($0.logicalWidth, $0.logicalHeight) }
        XCTAssertEqual(
            logical,
            [
                (2048, 1152),
                (1920, 1080),
                (1706, 960),
                (1600, 900),
                (1280, 720),
            ]
        )
        for mode in presets {
            XCTAssertEqual(mode.scale, 2)
            XCTAssertEqual(mode.pixelWidth, mode.logicalWidth * 2)
            XCTAssertEqual(mode.pixelHeight, mode.logicalHeight * 2)
            XCTAssertEqual(mode.logicalWidth % 2, 0)
            XCTAssertEqual(mode.logicalHeight % 2, 0)
        }
        XCTAssertTrue(presets[4].isPixelAligned(with: panel))
        XCTAssertFalse(presets[1].isPixelAligned(with: panel))
    }

    func testDefaultOn1440pIs1920x1080() {
        let panel = PanelPixels(width: 2560, height: 1440)
        let presets = ResolutionPlan.presets(for: panel)
        let chosen = ResolutionPlan.defaultPreset(for: panel, presets: presets)
        XCTAssertEqual(chosen, ScaledMode(logicalWidth: 1920, logicalHeight: 1080, scale: 2))
    }

    func testPresetsPreserveAspectAndStayInsideFramebufferCap() {
        let panels = [
            PanelPixels(width: 3440, height: 1440),
            PanelPixels(width: 1920, height: 1080),
            PanelPixels(width: 3840, height: 2160),
            PanelPixels(width: 1366, height: 768),
            PanelPixels(width: 7680, height: 4320),
        ]
        for panel in panels {
            let presets = ResolutionPlan.presets(for: panel)
            XCTAssertFalse(presets.isEmpty, "expected presets for \(panel)")
            for mode in presets {
                XCTAssertLessThanOrEqual(mode.pixelWidth, ResolutionPlan.maxFramebufferWidth)
                XCTAssertLessThanOrEqual(mode.pixelHeight, ResolutionPlan.maxFramebufferHeight)
                XCTAssertGreaterThanOrEqual(mode.logicalWidth, ResolutionPlan.minLogicalWidth)
                XCTAssertGreaterThanOrEqual(mode.logicalHeight, ResolutionPlan.minLogicalHeight)
                let aspect = Double(mode.logicalWidth) / Double(mode.logicalHeight)
                XCTAssertEqual(aspect, panel.aspectRatio, accuracy: 0.03)
            }
        }
    }

    func test8KPanelDropsModesAboveTheFramebufferCap() {
        let presets = ResolutionPlan.presets(for: PanelPixels(width: 7680, height: 4320))
        XCTAssertEqual(presets, [ScaledMode(logicalWidth: 3840, logicalHeight: 2160, scale: 2)])
    }

    func testEmptyPanelHasNoPresets() {
        XCTAssertTrue(ResolutionPlan.presets(for: PanelPixels(width: 0, height: 1440)).isEmpty)
        XCTAssertNil(ResolutionPlan.defaultPreset(for: PanelPixels(width: 0, height: 0), presets: []))
    }

    func testVirtualDisplayAttemptsUseChromiumSizingFirst() {
        let panel = PanelPixels(width: 2560, height: 1440)
        let mode = ScaledMode(logicalWidth: 1920, logicalHeight: 1080, scale: 2)
        let key = DisplayKey(vendorID: 0x10AC, productID: 0xD06E, serialNumber: 0x1234, unitNumber: 2)
        let attempts = ResolutionPlan.attempts(
            displayName: "DELL U2722D",
            panel: panel,
            mode: mode,
            refreshRate: 59.94,
            identity: key
        )
        XCTAssertEqual(attempts.count, 2)
        let first = attempts[0]
        XCTAssertEqual(first.kind, .logicalPoints)
        XCTAssertEqual(first.spec.hiDPI, true)
        XCTAssertEqual(first.spec.vendorID, 0x4844)
        XCTAssertEqual(first.spec.maxPixelsWide, 3840)
        XCTAssertEqual(first.spec.maxPixelsHigh, 2160)
        XCTAssertEqual(first.spec.modes, [VirtualMode(width: 1920, height: 1080, refreshRate: 60)])
        XCTAssertEqual(first.spec.name, "HiDPI DELL U2722D")
        XCTAssertEqual(first.spec.widthMillimeters, 3840.0 / 220.0 * 25.4, accuracy: 0.001)
        XCTAssertEqual(first.spec.heightMillimeters, 2160.0 / 220.0 * 25.4, accuracy: 0.001)

        let second = attempts[1]
        XCTAssertEqual(second.kind, .framebufferPixels)
        XCTAssertEqual(second.spec.maxPixelsWide, 3840)
        XCTAssertEqual(second.spec.modes, [VirtualMode(width: 3840, height: 2160, refreshRate: 60)])
        XCTAssertEqual(second.spec.productID, first.spec.productID)
        XCTAssertNotEqual(second.spec.productID, 0)
        XCTAssertNotEqual(second.spec.serialNumber, 0)
    }

    func testVirtualIdentityIsStableAndDistinct() {
        let key = DisplayKey(vendorID: 0x10AC, productID: 0xD06E, serialNumber: 0x1234, unitNumber: 2)
        let again = ResolutionPlan.virtualIdentity(for: key)
        let first = ResolutionPlan.virtualIdentity(for: key)
        XCTAssertEqual(first.productID, again.productID)
        XCTAssertEqual(first.serialNumber, again.serialNumber)
        XCTAssertEqual(first.productID, UInt32(2_242_745_137))
        XCTAssertEqual(first.serialNumber, UInt32(3_491_371_988))
        let other = DisplayKey(vendorID: 0x10AC, productID: 0xD06E, serialNumber: 0x1234, unitNumber: 3)
        XCTAssertNotEqual(ResolutionPlan.virtualIdentity(for: other).serialNumber, first.serialNumber)
    }

    func testRefreshRateNormalization() {
        XCTAssertEqual(ResolutionPlan.normalizedRefreshRate(59.94), 60)
        XCTAssertEqual(ResolutionPlan.normalizedRefreshRate(144), 144)
        XCTAssertEqual(ResolutionPlan.normalizedRefreshRate(0), 60)
        XCTAssertEqual(ResolutionPlan.normalizedRefreshRate(.nan), 60)
        XCTAssertEqual(ResolutionPlan.normalizedRefreshRate(500), 60)
    }

    func testDisplayNameSanitizing() {
        XCTAssertEqual(ResolutionPlan.sanitizedDisplayName("  DELL\nU2722D  "), "DELL U2722D")
        XCTAssertEqual(ResolutionPlan.sanitizedDisplayName("   "), "Display")
        let long = String(repeating: "A", count: 80)
        XCTAssertEqual(ResolutionPlan.sanitizedDisplayName(long).count, 40)
    }

    func testSavedModeResolvesOnlyExactPresets() {
        let presets = ResolutionPlan.presets(for: PanelPixels(width: 2560, height: 1440))
        let resolved = ResolutionPlan.resolveSavedMode(logicalWidth: 1600, logicalHeight: 900, presets: presets)
        XCTAssertEqual(resolved?.logicalWidth, 1600)
        XCTAssertNil(ResolutionPlan.resolveSavedMode(logicalWidth: 1111, logicalHeight: 1111, presets: presets))
    }
}
