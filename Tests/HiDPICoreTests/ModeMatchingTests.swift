import HiDPICore
import XCTest

final class ModeMatchingTests: XCTestCase {
    func testPicksExactTwoXModeAndClosestRefresh() {
        let modes = [
            DisplayModeSummary(width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, refreshRate: 60),
            DisplayModeSummary(width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 50),
            DisplayModeSummary(width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60),
            DisplayModeSummary(width: 1280, height: 720, pixelWidth: 2560, pixelHeight: 1440, refreshRate: 60),
        ]
        let match = ModeMatching.bestHiDPIMode(
            among: modes,
            logicalWidth: 1920,
            logicalHeight: 1080,
            refreshRate: 59.94
        )
        XCTAssertEqual(match?.refreshRate, 60)
        XCTAssertEqual(match?.pixelWidth, 3840)
        XCTAssertEqual(match?.isHiDPI, true)
    }

    func testNative1440pPicks5120FramebufferNotOneX() {
        let modes = [
            DisplayModeSummary(width: 2560, height: 1440, pixelWidth: 2560, pixelHeight: 1440, refreshRate: 60),
            DisplayModeSummary(width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60),
            DisplayModeSummary(width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 60),
        ]
        let match = ModeMatching.bestHiDPIMode(
            among: modes,
            logicalWidth: 2560,
            logicalHeight: 1440,
            refreshRate: 60
        )
        XCTAssertEqual(match?.width, 2560)
        XCTAssertEqual(match?.height, 1440)
        XCTAssertEqual(match?.pixelWidth, 5120)
        XCTAssertEqual(match?.pixelHeight, 2880)
        XCTAssertEqual(match?.isHiDPI, true)
    }

    func testIgnoresOneXModeWithTheSamePointSize() {
        let modes = [
            DisplayModeSummary(width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, refreshRate: 60)
        ]
        XCTAssertNil(
            ModeMatching.bestHiDPIMode(
                among: modes,
                logicalWidth: 1920,
                logicalHeight: 1080,
                refreshRate: 60
            )
        )
    }

    func testDescribeEmptyList() {
        XCTAssertEqual(ModeMatching.describe([]), "(none)")
        let line = ModeMatching.describe([
            DisplayModeSummary(width: 1280, height: 720, pixelWidth: 2560, pixelHeight: 1440, refreshRate: 60)
        ])
        XCTAssertTrue(line.contains("1280x720"))
        XCTAssertTrue(line.contains("2560x1440"))
    }
}
