import HiDPICore
import XCTest

final class PersistedStateTests: XCTestCase {
    func testRoundTripAndUpsert() {
        let key = DisplayKey(vendorID: 1, productID: 2, serialNumber: 3, unitNumber: 4)
        let session = PersistedSession(key: key, logicalWidth: 1920, logicalHeight: 1080)
        let state = PersistedState().upsert(session).upsert(
            PersistedSession(key: key, logicalWidth: 1600, logicalHeight: 900)
        )
        XCTAssertEqual(state.sessions.count, 1)
        XCTAssertEqual(state.sessions[0].logicalWidth, 1600)
        let data = state.encode()
        XCTAssertNotNil(data)
        let decoded = PersistedState.decode(from: data ?? Data())
        XCTAssertEqual(decoded, state)
        XCTAssertTrue(decoded.remove(key).sessions.isEmpty)
    }

    func testCorruptJSONDecodesAsEmpty() {
        let decoded = PersistedState.decode(from: Data("not json".utf8))
        XCTAssertEqual(decoded, PersistedState())
    }
}
