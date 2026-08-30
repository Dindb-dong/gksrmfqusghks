import Foundation

public struct CorrectionStatisticEntry: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let original: String
  public let replacement: String
  public let count: Int

  public init(
    id: UUID = UUID(),
    original: String,
    replacement: String,
    count: Int
  ) {
    self.id = id
    self.original = original
    self.replacement = replacement
    self.count = count
  }
}

public final class LocalCorrectionStatisticsStore {
  typealias PermissionHardener = (URL) throws -> Void

  private struct Document: Codable {
    let version: Int
    let entries: [CorrectionStatisticEntry]
  }

  public private(set) var entries: [CorrectionStatisticEntry] = []
  public private(set) var recoveredFromCorruption = false
  public private(set) var permissionHardeningFailed = false
  public let fileURL: URL
  private let permissionHardener: PermissionHardener

  public convenience init(fileURL: URL = LocalCorrectionStatisticsStore.defaultFileURL()) {
    self.init(fileURL: fileURL, permissionHardener: Self.hardenPermissions)
  }

  init(fileURL: URL, permissionHardener: @escaping PermissionHardener) {
    self.fileURL = fileURL
    self.permissionHardener = permissionHardener
    load()
  }

  public var totalCorrectionCount: Int {
    entries.reduce(into: 0) { total, entry in
      let (sum, overflow) = total.addingReportingOverflow(entry.count)
      total = overflow ? Int.max : sum
    }
  }

  public var sortedEntries: [CorrectionStatisticEntry] {
    entries.sorted {
      if $0.count != $1.count {
        return $0.count > $1.count
      }
      if $0.replacement != $1.replacement {
        return $0.replacement.localizedStandardCompare($1.replacement) == .orderedAscending
      }
      return $0.original.localizedStandardCompare($1.original) == .orderedAscending
    }
  }

  public func record(original: String, replacement: String) throws {
    guard
      let normalizedOriginal = Self.normalizedWord(original),
      let normalizedReplacement = Self.normalizedWord(replacement),
      normalizedOriginal != normalizedReplacement
    else {
      return
    }

    let previousEntries = entries
    if let index = entries.firstIndex(where: {
      $0.original == normalizedOriginal && $0.replacement == normalizedReplacement
    }) {
      let current = entries[index]
      let (incremented, overflow) = current.count.addingReportingOverflow(1)
      entries[index] = CorrectionStatisticEntry(
        id: current.id,
        original: current.original,
        replacement: current.replacement,
        count: overflow ? Int.max : incremented
      )
    } else {
      entries.append(
        CorrectionStatisticEntry(
          original: normalizedOriginal,
          replacement: normalizedReplacement,
          count: 1
        )
      )
    }

    do {
      try persist()
    } catch {
      entries = previousEntries
      throw error
    }
  }

  public func reset() throws {
    if FileManager.default.fileExists(atPath: fileURL.path) {
      try FileManager.default.removeItem(at: fileURL)
    }
    entries = []
  }

  public static func defaultFileURL() -> URL {
    let applicationSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    return
      applicationSupport
      .appendingPathComponent("HanKey", isDirectory: true)
      .appendingPathComponent("correction-statistics.json", isDirectory: false)
  }

  private func load() {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return
    }

    let document: Document
    do {
      document = try JSONDecoder().decode(
        Document.self,
        from: Data(contentsOf: fileURL)
      )
      guard document.version == 1 else {
        throw CocoaError(.fileReadCorruptFile)
      }
    } catch {
      recoveredFromCorruption = true
      let backupURL =
        fileURL
        .deletingPathExtension()
        .appendingPathExtension("corrupt-\(UUID().uuidString).json")
      try? FileManager.default.moveItem(at: fileURL, to: backupURL)
      entries = []
      return
    }
    entries = Self.sanitized(document.entries)
    do {
      try permissionHardener(fileURL)
    } catch {
      permissionHardeningFailed = true
    }
  }

  private func persist() throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(Document(version: 1, entries: entries)).write(
      to: fileURL,
      options: .atomic
    )
    try permissionHardener(fileURL)
    permissionHardeningFailed = false
  }

  private static func hardenPermissions(_ fileURL: URL) throws {
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: fileURL.deletingLastPathComponent().path
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: fileURL.path
    )
  }

  private static func normalizedWord(_ value: String) -> String? {
    let normalized = value.precomposedStringWithCanonicalMapping
    guard
      !normalized.isEmpty,
      normalized.count <= 64,
      !normalized.contains(where: { $0.isWhitespace || $0.isNewline })
    else {
      return nil
    }
    return normalized
  }

  private static func sanitized(
    _ loadedEntries: [CorrectionStatisticEntry]
  ) -> [CorrectionStatisticEntry] {
    var result: [CorrectionStatisticEntry] = []
    for entry in loadedEntries {
      guard
        let original = normalizedWord(entry.original),
        let replacement = normalizedWord(entry.replacement),
        original != replacement,
        entry.count > 0
      else {
        continue
      }
      if let index = result.firstIndex(where: {
        $0.original == original && $0.replacement == replacement
      }) {
        let existing = result[index]
        let (combined, overflow) = existing.count.addingReportingOverflow(entry.count)
        result[index] = CorrectionStatisticEntry(
          id: existing.id,
          original: existing.original,
          replacement: existing.replacement,
          count: overflow ? Int.max : combined
        )
      } else {
        result.append(
          CorrectionStatisticEntry(
            id: entry.id,
            original: original,
            replacement: replacement,
            count: entry.count
          )
        )
      }
    }
    return result
  }
}
