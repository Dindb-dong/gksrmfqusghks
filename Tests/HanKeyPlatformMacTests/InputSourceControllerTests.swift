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
  @MainActor
  func testSelectionRequiresActualSourceReadback() {
    let old = InputSourceSnapshot(
      identifier: InputSourceController.abcIdentifier, language: .english)
    let controller = InputSourceController(readSource: { old }, selectSource: { _ in true })
    XCTAssertNil(controller.select(language: .korean))
  }

  @MainActor
  func testSelectionFailsWhenCurrentSourceIsUnavailable() {
    let controller = InputSourceController(readSource: { nil }, selectSource: { _ in true })
    XCTAssertNil(controller.select(language: .korean))
  }

  @MainActor
  func testSelectionReturnsVerifiedSourceOnly() {
    let actual = InputSourceSnapshot(
      identifier: InputSourceController.korean2SetIdentifier, language: .korean)
    let controller = InputSourceController(readSource: { actual }, selectSource: { _ in true })
    XCTAssertEqual(controller.select(language: .korean), actual)
    let failed = InputSourceController(readSource: { actual }, selectSource: { _ in false })
    XCTAssertNil(failed.select(language: .korean))
  }

}
