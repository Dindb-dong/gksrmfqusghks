import Foundation
import XCTest

@testable import HanKeyPlatformMac

final class LocalCorrectionStatisticsStoreTests: XCTestCase {
  func testPersistsAndAggregatesSuccessfulCorrectionPairs() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("correction-statistics.json")

    let store = LocalCorrectionStatisticsStore(fileURL: fileURL)
    try store.record(original: "ㅁㅊㅁㅇ드ㅑㅊ", replacement: "academic")
    try store.record(original: "ㅅ미ㅏ", replacement: "talk")
    try store.record(original: "ㅁㅊㅁㅇ드ㅑㅊ", replacement: "academic")

    let reloaded = LocalCorrectionStatisticsStore(fileURL: fileURL)
    XCTAssertEqual(reloaded.totalCorrectionCount, 3)
    XCTAssertEqual(reloaded.sortedEntries.map(\.replacement), ["academic", "talk"])
    XCTAssertEqual(reloaded.sortedEntries.map(\.count), [2, 1])

    let fileMode = try XCTUnwrap(
      FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? NSNumber
    ).intValue
    XCTAssertEqual(fileMode & 0o777, 0o600)
  }

  func testInvalidOrUnchangedWordsAreNotPersisted() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("correction-statistics.json")
    let store = LocalCorrectionStatisticsStore(fileURL: fileURL)

    try store.record(original: "", replacement: "word")
    try store.record(original: "same", replacement: "same")
    try store.record(original: "two words", replacement: "word")

    XCTAssertEqual(store.totalCorrectionCount, 0)
    XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
  }

  func testFailedPersistenceRollsBackTheIncrement() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let blockedParent = directory.appendingPathComponent("not-a-directory")
    try Data("blocked".utf8).write(to: blockedParent)
    let store = LocalCorrectionStatisticsStore(
      fileURL: blockedParent.appendingPathComponent("statistics.json")
    )

    XCTAssertThrowsError(try store.record(original: "ㅅ미ㅏ", replacement: "talk"))
    XCTAssertTrue(store.entries.isEmpty)
  }

  func testResetRemovesPersistedStatistics() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("correction-statistics.json")
    let store = LocalCorrectionStatisticsStore(fileURL: fileURL)
    try store.record(original: "ㅅ미ㅏ", replacement: "talk")

    try store.reset()

    XCTAssertTrue(store.entries.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
  }

  func testCorruptedFileIsQuarantinedAndStartsEmpty() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let fileURL = directory.appendingPathComponent("correction-statistics.json")
    try Data("not-json".utf8).write(to: fileURL)

    let store = LocalCorrectionStatisticsStore(fileURL: fileURL)

    XCTAssertTrue(store.recoveredFromCorruption)
    XCTAssertTrue(store.entries.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    XCTAssertEqual(backups.filter { $0.contains(".corrupt-") }.count, 1)
  }

  func testPermissionHardeningFailureKeepsValidStatistics() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("correction-statistics.json")
    let writer = LocalCorrectionStatisticsStore(fileURL: fileURL)
    try writer.record(original: "ㅅ미ㅏ", replacement: "talk")

    let loaded = LocalCorrectionStatisticsStore(fileURL: fileURL) { _ in
      throw CocoaError(.fileWriteNoPermission)
    }

    XCTAssertEqual(loaded.totalCorrectionCount, 1)
    XCTAssertFalse(loaded.recoveredFromCorruption)
    XCTAssertTrue(loaded.permissionHardeningFailed)
    XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
  }
}
