import XCTest
@testable import CurveFanCore

final class IPCFramingTests: XCTestCase {
    func testEncodePrefixesPayloadWithBigEndianLength() throws {
        let payload = Data([0xAA, 0xBB, 0xCC])
        let frame = try IPCFraming.encode(payload)
        XCTAssertEqual(Array(frame.prefix(4)), [0x00, 0x00, 0x00, 0x03])
        XCTAssertEqual(Array(frame.dropFirst(4)), [0xAA, 0xBB, 0xCC])
    }

    func testDecodeLengthRejectsEmptyFrame() {
        XCTAssertThrowsError(try IPCFraming.decodeLength([0, 0, 0, 0])) { error in
            XCTAssertEqual(error as? IPCFramingError, .emptyFrame)
        }
    }

    func testDecodeLengthRejectsOversizedFrame() {
        let tooLarge = UInt32(IPCFraming.maxFrameSize + 1)
        let header = [
            UInt8((tooLarge >> 24) & 0xFF),
            UInt8((tooLarge >> 16) & 0xFF),
            UInt8((tooLarge >> 8) & 0xFF),
            UInt8(tooLarge & 0xFF)
        ]
        XCTAssertThrowsError(try IPCFraming.decodeLength(header))
    }
}
