import Testing
@testable import EnduranceDomain

@Suite("Toolchain probe")
struct ProbeTests {
    @Test("Swift Testing is available and the domain module links")
    func probe() {
        #expect(EnduranceDomain.productName == "Endurance")
        #expect(EnduranceDomain.currentPlanSchemaVersion == 1)
    }
}
