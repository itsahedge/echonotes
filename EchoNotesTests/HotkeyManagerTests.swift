import XCTest
@testable import EchoNotes

@MainActor
final class HotkeyManagerTests: XCTestCase {

    func testFourCharCodeProducesExpectedValues() {
        let manager = HotkeyManager()
        // "ECHO" → 0x4543484F
        let result = manager.fourCharCode("ECHO")
        XCTAssertEqual(result, 0x4543484F, "fourCharCode('ECHO') should be 0x4543484F")
    }

    func testFourCharCodeTruncatesLongStrings() {
        let manager = HotkeyManager()
        let four = manager.fourCharCode("ECHO")
        let long = manager.fourCharCode("ECHOEXTRA")
        XCTAssertEqual(four, long, "Only first 4 bytes should matter")
    }

    func testFourCharCodeHandlesShortStrings() {
        let manager = HotkeyManager()
        // "AB" → 0x4142
        let result = manager.fourCharCode("AB")
        XCTAssertEqual(result, 0x4142, "fourCharCode('AB') should be 0x4142")
    }

    func testFourCharCodeEmptyString() {
        let manager = HotkeyManager()
        let result = manager.fourCharCode("")
        XCTAssertEqual(result, 0, "fourCharCode('') should be 0")
    }

    func testRegisterUnregisterLifecycle() {
        let manager = HotkeyManager()
        var toggled = false
        manager.register { toggled = true }
        // Should not crash
        manager.unregister()
        XCTAssertFalse(toggled, "Callback should not fire from register/unregister alone")
    }

    func testDoubleUnregisterDoesNotCrash() {
        let manager = HotkeyManager()
        manager.register { }
        manager.unregister()
        manager.unregister() // Should not crash
    }
}
