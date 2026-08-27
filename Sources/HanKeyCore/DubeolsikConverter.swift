public enum DubeolsikConverter {
  private static let syllableBase: UInt32 = 0xAC00
  private static let syllableEnd: UInt32 = 0xD7A3
  private static let initialBase: UInt32 = 0x1100
  private static let medialBase: UInt32 = 0x1161
  private static let finalBase: UInt32 = 0x11A7
  private static let medialCount: UInt32 = 21
  private static let finalCount: UInt32 = 28

  public static func compose(_ qwerty: String) -> String {
    var composer = Composer()

    for character in qwerty {
      guard
        let token = PhysicalKeyToken(ascii: character),
        let jamo = DubeolsikTables.jamo(for: token)
      else {
        composer.flush()
        composer.output.append(character)
        continue
      }

      composer.process(jamo)
    }

    composer.flush()
    return composer.output
  }

  public static func compose(_ tokens: [PhysicalKeyToken]) -> String {
    var composer = Composer()
    for token in tokens {
      if let jamo = DubeolsikTables.jamo(for: token) {
        composer.process(jamo)
      }
    }
    composer.flush()
    return composer.output
  }

  public static func decomposeToQWERTY(_ text: String) -> String {
    var result = ""

    for scalar in text.unicodeScalars {
      let value = scalar.value

      if (syllableBase...syllableEnd).contains(value) {
        appendPrecomposedSyllable(value, to: &result)
      } else if let jamo = compatibilityJamo(forConjoiningScalar: value) {
        appendKeySequence(for: jamo, to: &result)
      } else {
        let character = Character(String(scalar))
        if DubeolsikTables.keySequenceByJamo[character] != nil {
          appendKeySequence(for: character, to: &result)
        } else {
          result.unicodeScalars.append(scalar)
        }
      }
    }

    return result
  }

  public static func oppositeLayoutCandidate(for text: String) -> String? {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty, normalized.count <= 64 else { return nil }

    let qwerty = decomposeToQWERTY(normalized)
    if qwerty != normalized {
      return qwerty
    }
    let hangul = compose(normalized)
    return hangul == normalized ? nil : hangul
  }

  private static func appendPrecomposedSyllable(_ scalar: UInt32, to result: inout String) {
    let syllableIndex = scalar - syllableBase
    let initialIndex = Int(syllableIndex / (medialCount * finalCount))
    let medialIndex = Int((syllableIndex % (medialCount * finalCount)) / finalCount)
    let finalIndex = Int(syllableIndex % finalCount)

    appendKeySequence(for: DubeolsikTables.initialJamo[initialIndex], to: &result)
    appendKeySequence(for: DubeolsikTables.medialJamo[medialIndex], to: &result)
    if let final = DubeolsikTables.finalJamo[finalIndex] {
      appendKeySequence(for: final, to: &result)
    }
  }

  private static func compatibilityJamo(forConjoiningScalar scalar: UInt32) -> Character? {
    if (initialBase...(initialBase + 18)).contains(scalar) {
      return DubeolsikTables.initialJamo[Int(scalar - initialBase)]
    }
    if (medialBase...(medialBase + 20)).contains(scalar) {
      return DubeolsikTables.medialJamo[Int(scalar - medialBase)]
    }
    if ((finalBase + 1)...(finalBase + 27)).contains(scalar) {
      return DubeolsikTables.finalJamo[Int(scalar - finalBase)]
    }
    return nil
  }

  private static func appendKeySequence(for jamo: Character, to result: inout String) {
    if let keys = DubeolsikTables.keySequenceByJamo[jamo] {
      result.append(keys)
    }
  }

  private struct Composer {
    var output = ""
    private var initial: Character?
    private var medial: Character?
    private var final: Character?

    mutating func process(_ jamo: Character) {
      if DubeolsikTables.medialIndex[jamo] != nil {
        processVowel(jamo)
      } else {
        processConsonant(jamo)
      }
    }

    mutating func flush() {
      commitCurrent()
    }

    private mutating func processConsonant(_ consonant: Character) {
      guard initial != nil || medial != nil else {
        initial = consonant
        return
      }

      guard initial != nil, medial != nil else {
        commitCurrent()
        initial = consonant
        return
      }

      guard let existingFinal = final else {
        if DubeolsikTables.finalIndex[consonant] != nil {
          final = consonant
        } else {
          commitCurrent()
          initial = consonant
        }
        return
      }

      let pair = JamoPair(first: existingFinal, second: consonant)
      if let combined = DubeolsikTables.compoundFinal[pair] {
        final = combined
      } else {
        commitCurrent()
        initial = consonant
      }
    }

    private mutating func processVowel(_ vowel: Character) {
      guard initial != nil || medial != nil else {
        medial = vowel
        return
      }

      if initial != nil, medial == nil {
        medial = vowel
        return
      }

      if initial == nil, let existingMedial = medial {
        let pair = JamoPair(first: existingMedial, second: vowel)
        if let combined = DubeolsikTables.compoundMedial[pair] {
          medial = combined
        } else {
          commitCurrent()
          medial = vowel
        }
        return
      }

      guard let existingMedial = medial else {
        medial = vowel
        return
      }

      guard let existingFinal = final else {
        let pair = JamoPair(first: existingMedial, second: vowel)
        if let combined = DubeolsikTables.compoundMedial[pair] {
          medial = combined
        } else {
          commitCurrent()
          medial = vowel
        }
        return
      }

      let split = DubeolsikTables.splitCompoundFinal[existingFinal]
      final = split?.first
      let movedInitial = split?.second ?? existingFinal
      commitCurrent()
      initial = movedInitial
      medial = vowel
    }

    private mutating func commitCurrent() {
      defer {
        initial = nil
        medial = nil
        final = nil
      }

      guard let initial else {
        if let medial {
          output.append(medial)
        }
        return
      }

      guard let medial else {
        output.append(initial)
        return
      }

      guard
        let initialIndex = DubeolsikTables.initialIndex[initial],
        let medialIndex = DubeolsikTables.medialIndex[medial]
      else {
        output.append(initial)
        output.append(medial)
        if let final {
          output.append(final)
        }
        return
      }

      let finalIndex = final.flatMap { DubeolsikTables.finalIndex[$0] } ?? 0
      let scalarValue =
        DubeolsikConverter.syllableBase
        + UInt32(initialIndex) * DubeolsikConverter.medialCount * DubeolsikConverter.finalCount
        + UInt32(medialIndex) * DubeolsikConverter.finalCount
        + UInt32(finalIndex)
      output.unicodeScalars.append(Unicode.Scalar(scalarValue)!)
    }
  }
}
