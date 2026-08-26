import Foundation
import HanKeyCore
import XCTest

@testable import HanKeyPlatformMac

final class LocalLearningStoreTests: XCTestCase {
  func testPersistsExplicitPairsAndExportsVersionedDocument() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("learning-rules.json")
    let exportURL = directory.appendingPathComponent("export.json")

    let store = LocalLearningStore(fileURL: fileURL)
    try store.upsert(original: "gksrmffh", replacement: "한글로", behavior: .always)
    XCTAssertTrue(try store.addExcludedApplication("com.example.Editor"))
    let reloaded = LocalLearningStore(fileURL: fileURL)
    XCTAssertEqual(reloaded.behavior(original: "gksrmffh", replacement: "한글로"), .always)
    XCTAssertTrue(reloaded.isApplicationExcluded("com.example.Editor"))

    try reloaded.export(to: exportURL)
    let exported = try String(contentsOf: exportURL, encoding: .utf8)
    XCTAssertTrue(exported.contains("\"version\" : 1"))
    XCTAssertTrue(exported.contains("gksrmffh"))
    XCTAssertTrue(exported.contains("com.example.Editor"))
  }

  func testInvalidApplicationIdentifiersAreRejectedAndResetClearsAllLocalData() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LocalLearningStore(fileURL: directory.appendingPathComponent("rules.json"))

    XCTAssertFalse(try store.addExcludedApplication("not a bundle"))
    XCTAssertTrue(try store.addExcludedApplication("com.example.Editor"))
    try store.upsert(original: "abc", replacement: "ㅁㅠㅊ", behavior: .never)
    try store.reset()

    XCTAssertTrue(store.excludedApplicationBundleIdentifiers.isEmpty)
    XCTAssertTrue(store.rules.entries.isEmpty)
  }

  func testCorruptedFileIsQuarantinedAndStartsEmpty() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let fileURL = directory.appendingPathComponent("learning-rules.json")
    try Data("not-json".utf8).write(to: fileURL)

    let store = LocalLearningStore(fileURL: fileURL)
    XCTAssertTrue(store.recoveredFromCorruption)
    XCTAssertTrue(store.rules.entries.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    XCTAssertEqual(backups.filter { $0.contains(".corrupt-") }.count, 1)
  }
}
