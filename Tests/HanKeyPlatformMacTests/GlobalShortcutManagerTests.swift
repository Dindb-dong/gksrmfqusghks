import XCTest

@testable import HanKeyPlatformMac

final class GlobalShortcutManagerTests: XCTestCase {
  func testPresetsHaveStableUserFacingTitles() {
    XCTAssertEqual(ShortcutPreset.none.title, "지정 안 됨")
    XCTAssertEqual(ShortcutPreset.optionSpace.title, "⌥Space")
    XCTAssertEqual(ShortcutPreset.controlOptionSpace.title, "⌃⌥Space")
    XCTAssertEqual(ShortcutPreset.shiftOptionSpace.title, "⇧⌥Space")
    XCTAssertEqual(ShortcutPreset.controlOptionU.title, "⌃⌥U")
  }

  func testConfigurationRejectsOnlyEnabledInternalCollision() {
    XCTAssertTrue(
      ShortcutConfiguration(
        manualConvert: .optionSpace,
        undo: .optionSpace
      ).hasInternalCollision
    )
    XCTAssertFalse(
      ShortcutConfiguration(
        manualConvert: .none,
        undo: .none
      ).hasInternalCollision
    )
    XCTAssertFalse(
      ShortcutConfiguration(
        manualConvert: .optionSpace,
        undo: .controlOptionU
      ).hasInternalCollision
    )
  }
}
