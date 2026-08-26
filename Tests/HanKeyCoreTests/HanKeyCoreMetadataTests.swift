import HanKeyCore
import XCTest

final class HanKeyCoreMetadataTests: XCTestCase {
  func testInitialProductContract() {
    XCTAssertEqual(HanKeyCoreMetadata.displayName, "한글변환")
    XCTAssertEqual(HanKeyCoreMetadata.initialVersion, "0.1.0")
    XCTAssertEqual(HanKeyCoreMetadata.supportedInputSources, ["ABC", "2-Set Korean"])
  }
}
