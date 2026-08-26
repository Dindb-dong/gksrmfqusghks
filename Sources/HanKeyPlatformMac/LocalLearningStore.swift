import Foundation
import HanKeyCore

public final class LocalLearningStore {
  private struct Document: Codable {
    let version: Int
    let entries: [LearningRuleEntry]
  }

  public private(set) var rules: LearningRuleSet
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

  public func reset() throws {
    rules = LearningRuleSet()
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
    } catch {
      recoveredFromCorruption = true
      let backupURL =
        fileURL
        .deletingPathExtension()
        .appendingPathExtension("corrupt-\(UUID().uuidString).json")
      try? FileManager.default.moveItem(at: fileURL, to: backupURL)
      rules = LearningRuleSet()
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
    return try encoder.encode(Document(version: 1, entries: rules.entries))
  }
}
