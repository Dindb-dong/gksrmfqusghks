import HanKeyCore
import XCTest

final class SoftwareUpdateConfigurationTests: XCTestCase {
  private let validKey = "zeXCwsoulbNVILZmiIOj9zR3C3eYoL+Bs8N/VIJaWts="

  func testAcceptsHTTPSFeedAnd32ByteEdDSAPublicKey() throws {
    let configuration = try XCTUnwrap(
      SoftwareUpdateConfiguration(
        feedURLString:
          "https://github.com/Dindb-dong/gksrmfqusghks/releases/latest/download/appcast.xml",
        publicEDKey: validKey
      )
    )

    XCTAssertEqual(configuration.feedURL.scheme, "https")
    XCTAssertEqual(configuration.feedURL.lastPathComponent, "appcast.xml")
  }

  func testRejectsInsecurePlaceholderAndMalformedConfigurations() {
    XCTAssertNil(
      SoftwareUpdateConfiguration(
        feedURLString: "http://example.com/appcast.xml",
        publicEDKey: validKey
      )
    )
    XCTAssertNil(
      SoftwareUpdateConfiguration(
        feedURLString: "$(SPARKLE_FEED_URL)",
        publicEDKey: validKey
      )
    )
    XCTAssertNil(
      SoftwareUpdateConfiguration(
        feedURLString: "https://example.com/appcast.xml",
        publicEDKey: "not-a-key"
      )
    )
  }
}
