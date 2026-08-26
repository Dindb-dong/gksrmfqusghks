import HanKeyCore
import XCTest

@testable import HanKeyPlatformMac

final class InputSourceControllerTests: XCTestCase {
  func testUsesStableIdentifiersInsteadOfDisplayNames() {
    XCTAssertEqual(
      InputSourceController.language(forIdentifier: InputSourceController.abcIdentifier),
      .english
    )
    XCTAssertEqual(
      InputSourceController.language(forIdentifier: InputSourceController.korean2SetIdentifier),
      .korean
    )
    XCTAssertNil(InputSourceController.language(forIdentifier: "localized.display.name"))
    XCTAssertEqual(
      InputSourceController.identifier(for: .english), InputSourceController.abcIdentifier)
    XCTAssertEqual(
      InputSourceController.identifier(for: .korean),
      InputSourceController.korean2SetIdentifier
    )
  }
}
