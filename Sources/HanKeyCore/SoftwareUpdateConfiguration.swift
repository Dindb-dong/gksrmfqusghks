import Foundation

public struct SoftwareUpdateConfiguration: Equatable, Sendable {
  public let feedURL: URL
  public let publicEDKey: String

  public init?(feedURLString: String, publicEDKey: String) {
    guard
      let feedURL = URL(string: feedURLString),
      feedURL.scheme == "https",
      feedURL.host != nil,
      !feedURLString.contains("$("),
      let keyData = Data(base64Encoded: publicEDKey),
      keyData.count == 32
    else {
      return nil
    }
    self.feedURL = feedURL
    self.publicEDKey = publicEDKey
  }
}
