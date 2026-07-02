import XCTest
@testable import CurveFanCore

// Minimal transport double for injection testing.
private struct FailingTransport: IPCTransport {
    func roundTrip(_ data: Data) async throws -> Data {
        throw IPCError.noResponse
    }
}

final class IPCInjectionTests: XCTestCase {

    func testTemperatureReaderAcceptsInjectedClient() async {
        let transport = FailingTransport()
        let client = IPCClient(transport: transport)
        let reader = TemperatureReader(ipc: client)

        // Should not be the shared singleton.
        // We exercise the injected path; it will fail at transport and return empty.
        let readings = await reader.readings(for: .m5Gen)
        XCTAssertTrue(readings.isEmpty)
    }

    func testFanControllerAcceptsInjectedClient() async {
        let transport = FailingTransport()
        let client = IPCClient(transport: transport)
        let controller = FanController(ipc: client)

        // Exercise a throwing path using the injected client.
        do {
            _ = try await controller.getFanInfo(0)
            XCTFail("Expected throw from injected failing transport")
        } catch {
            // Success: the injected client was used (real shared would try real socket).
            XCTAssertTrue(error is IPCError || (error as? IPCError) != nil || error.localizedDescription.contains("No response"))
        }
    }
}
