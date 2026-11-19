import XCTest
@testable import vezzi_ios

final class AddressDisplayTests: XCTestCase {
    func testUppercasesOnlyFirstLetter() {
        XCTAssertEqual("  улица Генерала Хрулёва, 12 литА\n".addressCapitalized, "Улица Генерала Хрулёва, 12 литА")
        XCTAssertEqual("street of NASA, 4b".addressCapitalized, "Street of NASA, 4b")
        XCTAssertEqual("12-я линия В.О., 3".addressCapitalized, "12-я линия В.О., 3")
        XCTAssertEqual("«зелёная» улица".addressCapitalized, "«Зелёная» улица")
        XCTAssertEqual("".addressCapitalized, "")
        XCTAssertEqual(" 123 ".addressCapitalized, "123")
    }

    func testStoreAddressCapitalizationFollowsCityRemoval() {
        let raw = "Санкт-Петербург, комендантский проспект, 12 литА"
        XCTAssertEqual(StoreDisplayText.address(raw), "Комендантский проспект, 12 литА")
        XCTAssertEqual(raw, "Санкт-Петербург, комендантский проспект, 12 литА")
        XCTAssertNil(StoreDisplayText.address("   "))
    }
}
