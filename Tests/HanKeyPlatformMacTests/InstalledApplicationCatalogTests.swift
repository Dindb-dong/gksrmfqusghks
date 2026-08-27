import Foundation
import XCTest

@testable import HanKeyPlatformMac

final class InstalledApplicationCatalogTests: XCTestCase {
  func testDiscoversNamesSortsAndDeduplicatesBundleIdentifiers() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try makeApplication(named: "Zulu", identifier: "com.example.shared", in: root)
    try makeApplication(named: "Alpha", identifier: "com.example.alpha", in: root)
    try makeApplication(named: "Duplicate", identifier: "com.example.shared", in: root)

    let applications = InstalledApplicationCatalog.discover(roots: [root])

    XCTAssertEqual(applications.count, 2)
    XCTAssertEqual(applications.first?.displayName, "Alpha")
    XCTAssertTrue(["Duplicate", "Zulu"].contains(applications.last?.displayName ?? ""))
    XCTAssertEqual(Set(applications.map(\.bundleIdentifier)).count, 2)
  }

  private func makeApplication(named name: String, identifier: String, in root: URL) throws {
    let contents = root.appendingPathComponent("\(name).app/Contents", isDirectory: true)
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let plist: [String: Any] = [
      "CFBundleIdentifier": identifier,
      "CFBundleName": name,
      "CFBundlePackageType": "APPL",
    ]
    let data = try PropertyListSerialization.data(
      fromPropertyList: plist,
      format: .xml,
      options: 0
    )
    try data.write(to: contents.appendingPathComponent("Info.plist"))
  }
}
