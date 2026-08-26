import Foundation
import HanKeyCore

public final class LocalLearningStore {
  private struct Document: Codable {
    let version: Int
    let entries: [LearningRuleEntry]
    let excludedApplications: [String]

    init(version: Int, entries: [LearningRuleEntry], excludedApplications: [String]) {
      self.version = version
      self.entries = entries
      self.excludedApplications = excludedApplications
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      version = try container.decode(Int.self, forKey: .version)
      entries = try container.decode([LearningRuleEntry].self, forKey: .entries)
      excludedApplications =
        try container.decodeIfPresent(
          [String].self,
          forKey: .excludedApplications
        ) ?? []
    }
  }

  public private(set) var rules: LearningRuleSet
  public private(set) var excludedApplicationBundleIdentifiers: [String] = []
  public private(set) var recoveredFromCorruption = false
  public let fileURL: URL

  public init(fileURL: URL = LocalLearningStore.defaultFileURL()) {
    self.fileURL = fileURL
    rules = LearningRuleSet()
    load()
  }

  public func behavior(original: String, replacement: String) -> LearningRuleBehavior? {
    rules.behavior(original: original, replacement: replacement)
  }

  public func isApplicationExcluded(_ bundleIdentifier: String?) -> Bool {
    guard let bundleIdentifier else { return true }
    return excludedApplicationBundleIdentifiers.contains(bundleIdentifier)
  }

  @discardableResult
  public func upsert(
    original: String,
    replacement: String,
    behavior: LearningRuleBehavior
  ) throws -> LearningRuleEntry? {
    guard
      let entry = rules.upsert(
        original: original,
        replacement: replacement,
        behavior: behavior
      )
    else {
      return nil
    }
    try persist()
    return entry
  }

  public func remove(id: UUID) throws {
    rules.remove(id: id)
    try persist()
  }

  @discardableResult
  public func addExcludedApplication(_ bundleIdentifier: String) throws -> Bool {
    let normalized = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
    guard
      normalized.count >= 3,
      normalized.count <= 255,
      normalized.contains("."),
      normalized.unicodeScalars.allSatisfy({ allowed.contains($0) })
    else {
      return false
    }
    guard !excludedApplicationBundleIdentifiers.contains(normalized) else {
      return true
    }
    excludedApplicationBundleIdentifiers.append(normalized)
    excludedApplicationBundleIdentifiers.sort()
    try persist()
    return true
  }

  public func removeExcludedApplication(_ bundleIdentifier: String) throws {
    excludedApplicationBundleIdentifiers.removeAll { $0 == bundleIdentifier }
    try persist()
  }

  public func reset() throws {
    rules = LearningRuleSet()
    excludedApplicationBundleIdentifiers = []
    if FileManager.default.fileExists(atPath: fileURL.path) {
      try FileManager.default.removeItem(at: fileURL)
    }
  }

  public func export(to destination: URL) throws {
    try encodedDocument().write(to: destination, options: .atomic)
  }

  public static func defaultFileURL() -> URL {
    let applicationSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    return
      applicationSupport
      .appendingPathComponent("HanKey", isDirectory: true)
      .appendingPathComponent("learning-rules.json", isDirectory: false)
  }

  private func load() {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return
    }
    do {
      let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: fileURL))
      guard document.version == 1 else {
        throw CocoaError(.fileReadCorruptFile)
      }
      rules = LearningRuleSet(entries: document.entries)
      excludedApplicationBundleIdentifiers = document.excludedApplications.filter {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        return $0.count >= 3 && $0.count <= 255 && $0.contains(".")
          && $0.unicodeScalars.allSatisfy { allowed.contains($0) }
      }
    } catch {
      recoveredFromCorruption = true
      let backupURL =
        fileURL
        .deletingPathExtension()
        .appendingPathExtension("corrupt-\(UUID().uuidString).json")
      try? FileManager.default.moveItem(at: fileURL, to: backupURL)
      rules = LearningRuleSet()
      excludedApplicationBundleIdentifiers = []
    }
  }

  private func persist() throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try encodedDocument().write(to: fileURL, options: .atomic)
  }

  private func encodedDocument() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(
      Document(
        version: 1,
        entries: rules.entries,
        excludedApplications: excludedApplicationBundleIdentifiers
      )
    )
  }
}
