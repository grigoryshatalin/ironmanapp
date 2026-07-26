import XCTest
import EnduranceDomain
@testable import Endurance

/// Unit tests for the app layer's pure helpers. The heavy domain logic is tested
/// in EnduranceDomainTests (57 tests); these cover app-only glue.
final class AppUnitTests: XCTestCase {

    func testDeepLinkParsing() {
        XCTAssertEqual(DeepLink(path: "today"), .today)
        let id = UUID()
        XCTAssertEqual(DeepLink(path: "workout/\(id.uuidString)"), .workout(id))
        XCTAssertEqual(DeepLink(path: "review/8"), .review(8))
        XCTAssertNil(DeepLink(path: "bogus"))
        XCTAssertNil(DeepLink(path: "workout/not-a-uuid"))
    }

    func testDeepLinkFromURL() {
        let url = URL(string: "endurance://review/12")!
        XCTAssertEqual(DeepLink(url: url), .review(12))
        XCTAssertNil(DeepLink(url: URL(string: "https://example.com/review/12")!))
    }

    func testDisplayFormatterDuration() {
        let fmt = DisplayFormatter(units: .metric)
        XCTAssertEqual(fmt.duration(minutes: 90), "1h 30m")
    }

    func testDisplayFormatterDistanceRespectsUnits() {
        let imperial = DisplayFormatter(units: .imperial)
        // A pool swim in imperial shows yards.
        let s = imperial.distance(1828.8, sport: .swim)
        XCTAssertNotNil(s)
        XCTAssertTrue(s!.contains("yd"))
    }
}
