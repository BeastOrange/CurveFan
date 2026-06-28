import XCTest
@testable import CurveFanCore

final class SMCKeyDBTests: XCTestCase {
    func testFanKeysExist() {
        let fanKeys = SMCKeyDB.fanKeys
        XCTAssertTrue(fanKeys.contains { $0.key == "FNum" })
        XCTAssertTrue(fanKeys.contains { $0.key == "F0Ac" })
        XCTAssertTrue(fanKeys.contains { $0.key == "F0Mn" })
        XCTAssertTrue(fanKeys.contains { $0.key == "F0Mx" })
        XCTAssertTrue(fanKeys.contains { $0.key == "F0Tg" })
        XCTAssertTrue(fanKeys.contains { $0.key == "Ftst" })
    }

    func testKeysForPlatform() {
        let m1Keys = SMCKeyDB.keys(for: .m1Gen)
        XCTAssertFalse(m1Keys.isEmpty)
    }

    func testKeysForGroup() {
        let cpuKeys = SMCKeyDB.keys(for: .cpu, chip: .m1Gen)
        XCTAssertFalse(cpuKeys.isEmpty)
        XCTAssertTrue(cpuKeys.allSatisfy { $0.group == .cpu })
    }

    func testDefinitionLookup() {
        let def = SMCKeyDB.definition(for: "FNum")
        XCTAssertNotNil(def)
        XCTAssertEqual(def?.key, "FNum")
        XCTAssertEqual(def?.group, .fan)
        XCTAssertEqual(def?.type, .ui8)
    }

    func testDefinitionNotFound() {
        XCTAssertNil(SMCKeyDB.definition(for: "XXXX"))
    }

    func testM5FanModeKey() {
        let key = SMCKeyDB.writableFanModeKey(for: 0, chip: .m5Gen)
        XCTAssertEqual(key, "F0md")
    }

    func testM1FanModeKey() {
        let key = SMCKeyDB.writableFanModeKey(for: 0, chip: .m1Gen)
        XCTAssertEqual(key, "F0Md")
    }

    func testKeysUniquePerPlatform() {
        for chip in ChipGen.allCases {
            let keys = SMCKeyDB.keys(for: chip).map(\.key)
            let uniques = Set(keys)
            XCTAssertEqual(keys.count, uniques.count, "Duplicate keys found for \(chip)")
        }
    }
}
