import XCTest

@MainActor
extension XCTestCase {

    /// Existence is not enough before tapping: the Continue button exists on
    /// every onboarding step, so under simulator load a tap can be synthesized
    /// before the previous step has settled — which shows up as "Timed out while
    /// synthesizing event". Wait for hittability instead.
    @discardableResult
    func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 15) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
