import Foundation
import HanKeyCore

public final class LocalLearningStore {
  typealias PermissionHardener = (URL) throws -> Void

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
  public private(set) var permissionHardeningFailed = false
  public let fileURL: URL
  private let permissionHardener: PermissionHardener

  public convenience init(fileURL: URL = LocalLearningStore.defaultFileURL()) {
    self.init(fileURL: fileURL, permissionHardener: Self.hardenPermissions)
  }

  init(fileURL: URL, permissionHardener: @escaping PermissionHardener) {
    self.fileURL = fileURL
    self.permissionHardener = permissionHardener
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
    let previousRules = rules
    guard
      let entry = rules.upsert(
        original: original,
        replacement: replacement,
        behavior: behavior
      )
    else {
      return nil
    }
    do {
      try persist()
    } catch {
      rules = previousRules
      throw error
    }
    return entry
  }

  public func remove(id: UUID) throws {
    let previousRules = rules
    rules.remove(id: id)
    do {
      try persist()
    } catch {
      rules = previousRules
      throw error
    }
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
    let previousApplications = excludedApplicationBundleIdentifiers
    excludedApplicationBundleIdentifiers.append(normalized)
    excludedApplicationBundleIdentifiers.sort()
    do {
      try persist()
    } catch {
      excludedApplicationBundleIdentifiers = previousApplications
      throw error
    }
    return true
  }

  public func removeExcludedApplication(_ bundleIdentifier: String) throws {
    let previousApplications = excludedApplicationBundleIdentifiers
    excludedApplicationBundleIdentifiers.removeAll { $0 == bundleIdentifier }
    do {
      try persist()
    } catch {
      excludedApplicationBundleIdentifiers = previousApplications
      throw error
    }
  }

  public func reset() throws {
    if FileManager.default.fileExists(atPath: fileURL.path) {
      try FileManager.default.removeItem(at: fileURL)
    }
    rules = LearningRuleSet()
    excludedApplicationBundleIdentifiers = []
  }

  public func export(to destination: URL) throws {
    try encodedDocument().write(to: destination, options: .atomic)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: destination.path
    )
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
    let document: Document
    do {
      document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: fileURL))
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
      rules = LearningRuleSet()
      excludedApplicationBundleIdentifiers = []
      return
    }

    rules = LearningRuleSet(entries: document.entries)
    excludedApplicationBundleIdentifiers = Array(
      Set(
        document.excludedApplications.filter {
          let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
          return $0.count >= 3 && $0.count <= 255 && $0.contains(".")
            && $0.unicodeScalars.allSatisfy { allowed.contains($0) }
        })
    ).sorted()
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
    try encodedDocument().write(to: fileURL, options: .atomic)
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
