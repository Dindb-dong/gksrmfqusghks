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

    let fileMode = try XCTUnwrap(
      FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? NSNumber
    ).intValue
    let directoryMode = try XCTUnwrap(
      FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
    ).intValue
    XCTAssertEqual(fileMode & 0o777, 0o600)
    XCTAssertEqual(directoryMode & 0o777, 0o700)
  }

  func testFailedPersistenceRollsBackInMemoryRulesAndExclusions() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let blockedParent = directory.appendingPathComponent("not-a-directory")
    try Data("blocked".utf8).write(to: blockedParent)
    let store = LocalLearningStore(fileURL: blockedParent.appendingPathComponent("rules.json"))

    XCTAssertThrowsError(
      try store.upsert(original: "gksrmffh", replacement: "한글로", behavior: .always)
    )
    XCTAssertTrue(store.rules.entries.isEmpty)
    XCTAssertThrowsError(try store.addExcludedApplication("com.example.Editor"))
    XCTAssertTrue(store.excludedApplicationBundleIdentifiers.isEmpty)
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

  func testPermissionHardeningFailureKeepsValidRulesWithoutMislabelingCorruption() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("learning-rules.json")
    let writer = LocalLearningStore(fileURL: fileURL)
    try writer.upsert(original: "gksrmffh", replacement: "한글로", behavior: .never)

    let loaded = LocalLearningStore(fileURL: fileURL) { _ in
      throw CocoaError(.fileWriteNoPermission)
    }

    XCTAssertEqual(loaded.behavior(original: "gksrmffh", replacement: "한글로"), .never)
    XCTAssertFalse(loaded.recoveredFromCorruption)
    XCTAssertTrue(loaded.permissionHardeningFailed)
    XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    XCTAssertTrue(backups.allSatisfy { !$0.contains(".corrupt-") })
  }
}
