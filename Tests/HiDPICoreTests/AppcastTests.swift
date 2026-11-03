import HiDPICore
import XCTest

final class ReleaseVersionTests: XCTestCase {
    func testParseAcceptsTagOrBareVersion() {
        XCTAssertEqual(ReleaseVersion.parse("v1.2.3"), "1.2.3")
        XCTAssertEqual(ReleaseVersion.parse("1.2.3"), "1.2.3")
        XCTAssertEqual(ReleaseVersion.parse("  V0.1.0 "), "0.1.0")
    }

    func testParseRejectsPrereleaseAndLeadingZeros() {
        XCTAssertNil(ReleaseVersion.parse("v1.2"))
        XCTAssertNil(ReleaseVersion.parse("1.2.3-beta"))
        XCTAssertNil(ReleaseVersion.parse("01.2.3"))
        XCTAssertNil(ReleaseVersion.parse(""))
    }
}

final class AppcastTests: XCTestCase {
    func testXMLIncludesVersionAndOmitsMissingSignature() {
        let release = sample(signature: nil)
        let xml = Appcast.xml(for: release)
        XCTAssertTrue(xml.contains("<sparkle:version>1.2.3</sparkle:version>"))
        XCTAssertTrue(xml.contains("<sparkle:shortVersionString>1.2.3</sparkle:shortVersionString>"))
        XCTAssertTrue(xml.contains("<sparkle:minimumSystemVersion>13.0.0</sparkle:minimumSystemVersion>"))
        XCTAssertTrue(xml.contains("Thu, 01 Jan 1970 00:00:00 +0000"))
        XCTAssertTrue(xml.contains("url=\"https://example.com/HiDPI-1.2.3.zip?x=1&amp;y=2\""))
        XCTAssertFalse(xml.contains("edSignature"))
        XCTAssertTrue(xml.contains("A & B"))
        XCTAssertTrue(xml.contains("length=\"42\""))
    }

    func testXMLIncludesEdSignature() {
        let xml = Appcast.xml(for: sample(signature: "abc+def/ghi="))
        XCTAssertTrue(xml.contains("sparkle:edSignature=\"abc+def/ghi=\""))
    }

    func testCDATADoesNotCloseEarly() {
        var release = sample(signature: "sig")
        release.notesHTML = "before ]]> after"
        let xml = Appcast.xml(for: release)
        XCTAssertTrue(xml.contains("before ]]]]><![CDATA[> after"))
        XCTAssertTrue(xml.contains("<![CDATA["))
    }

    private func sample(signature: String?) -> AppcastRelease {
        AppcastRelease(
            version: "1.2.3",
            title: "HiDPI 1.2.3",
            notesHTML: "<p>A & B</p>",
            feedURL: "https://example.com/appcast.xml",
            enclosureURL: "https://example.com/HiDPI-1.2.3.zip?x=1&y=2",
            length: 42,
            edSignature: signature,
            pubDate: Date(timeIntervalSince1970: 0)
        )
    }
}
