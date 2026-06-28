import XCTest
@testable import CurveFanCore

final class SMCDecoderTests: XCTestCase {
    func testDecodeFPE2() throws {
        let decoder = SMCDecoder.shared
        let result = try decoder.decode(type: .fpe2, bytes: [0x00, 0x10])
        XCTAssertEqual(result, 4.0, accuracy: 0.01)
    }

    func testDecodeFPE2Max() throws {
        let decoder = SMCDecoder.shared
        let result = try decoder.decode(type: .fpe2, bytes: [0xFF, 0xFF])
        XCTAssertEqual(result, 16383.75, accuracy: 0.01)
    }

    func testDecodeSP78() throws {
        let decoder = SMCDecoder.shared
        let result = try decoder.decode(type: .sp78, bytes: [0x10, 0x00])
        XCTAssertEqual(result, 16.0, accuracy: 0.1)
    }

    func testDecodeSP78Negative() throws {
        let decoder = SMCDecoder.shared
        let result = try decoder.decode(type: .sp78, bytes: [0xFE, 0x00])
        XCTAssertEqual(result, -2.0, accuracy: 0.1)
    }

    func testDecodeFLT() throws {
        let decoder = SMCDecoder.shared
        let bits = Float(42.5).bitPattern.littleEndian
        let bytes = withUnsafeBytes(of: bits) { Array($0) }
        let result = try decoder.decode(type: .flt, bytes: bytes)
        XCTAssertEqual(result, 42.5, accuracy: 0.01)
    }

    func testDecodeAppleSMCFloatBytes() throws {
        let actualRPM = try SMCDecoder.shared.decode(type: .flt, bytes: [231, 184, 27, 69])
        let maxRPM = try SMCDecoder.shared.decode(type: .flt, bytes: [0, 176, 204, 69])
        XCTAssertEqual(actualRPM, 2491.56, accuracy: 0.01)
        XCTAssertEqual(maxRPM, 6550.0, accuracy: 0.01)
    }

    func testDecodeUI8() throws {
        let result = try SMCDecoder.shared.decode(type: .ui8, bytes: [42])
        XCTAssertEqual(result, 42.0)
    }

    func testDecodeUI16() throws {
        let result = try SMCDecoder.shared.decode(type: .ui16, bytes: [0x10, 0x00])
        XCTAssertEqual(result, 4096.0)
    }

    func testDecodeUI32() throws {
        let result = try SMCDecoder.shared.decode(type: .ui32, bytes: [0x00, 0x01, 0x00, 0x00])
        XCTAssertEqual(result, 65536.0)
    }

    func testEncodeFLTRoundtrip() throws {
        let original: Double = 1234.5
        let bytes = try SMCDecoder.shared.encode(original, as: .flt)
        let decoded = try SMCDecoder.shared.decode(type: .flt, bytes: bytes)
        XCTAssertEqual(decoded, original, accuracy: 0.1)
    }

    func testEncodeUI8Roundtrip() throws {
        let bytes = try SMCDecoder.shared.encode(42, as: .ui8)
        let decoded = try SMCDecoder.shared.decode(type: .ui8, bytes: bytes)
        XCTAssertEqual(decoded, 42)
    }

    func testDecodeInsufficientBytes() {
        XCTAssertThrowsError(try SMCDecoder.shared.decode(type: .fpe2, bytes: [0x01]))
        XCTAssertThrowsError(try SMCDecoder.shared.decode(type: .flt, bytes: [0x01, 0x02]))
    }

    func testDecodeRawValue() throws {
        let result = try SMCDecoder.shared.decode(rawValue: 0x66706532, bytes: [0x00, 0x10])
        XCTAssertEqual(result, 4.0, accuracy: 0.01)
    }

    func testDecodeUnknownRawValue() {
        XCTAssertThrowsError(try SMCDecoder.shared.decode(rawValue: 0xDEADBEEF, bytes: [0x00]))
    }
}
