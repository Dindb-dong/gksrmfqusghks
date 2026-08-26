import Foundation

public enum LearningRuleBehavior: String, Codable, CaseIterable, Equatable, Sendable {
  case always
  case never

  public var explicitRule: ExplicitCorrectionRule {
    switch self {
    case .always: .always
    case .never: .never
    }
  }
}

public struct LearningRuleEntry: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let original: String
  public let replacement: String
  public let behavior: LearningRuleBehavior

  public init(
    id: UUID = UUID(),
    original: String,
    replacement: String,
    behavior: LearningRuleBehavior
  ) {
    self.id = id
    self.original = original
    self.replacement = replacement
    self.behavior = behavior
  }
}

public struct LearningRuleSet: Equatable, Sendable {
  public private(set) var entries: [LearningRuleEntry]

  public init(entries: [LearningRuleEntry] = []) {
    self.entries = entries
  }

  public func behavior(original: String, replacement: String) -> LearningRuleBehavior? {
    entries.first {
      $0.original == original && $0.replacement == replacement
    }?.behavior
  }

  @discardableResult
  public mutating func upsert(
    original: String,
    replacement: String,
    behavior: LearningRuleBehavior
  ) -> LearningRuleEntry? {
    let normalizedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      !normalizedOriginal.isEmpty,
      !normalizedReplacement.isEmpty,
      normalizedOriginal.count <= 64,
      normalizedReplacement.count <= 64,
      normalizedOriginal != normalizedReplacement
    else {
      return nil
    }

    entries.removeAll {
      $0.original == normalizedOriginal && $0.replacement == normalizedReplacement
    }
    let entry = LearningRuleEntry(
      original: normalizedOriginal,
      replacement: normalizedReplacement,
      behavior: behavior
    )
    entries.append(entry)
    entries.sort {
      if $0.original == $1.original {
        return $0.replacement.localizedStandardCompare($1.replacement) == .orderedAscending
      }
      return $0.original.localizedStandardCompare($1.original) == .orderedAscending
    }
    return entry
  }

  public mutating func remove(id: UUID) {
    entries.removeAll { $0.id == id }
  }
}
