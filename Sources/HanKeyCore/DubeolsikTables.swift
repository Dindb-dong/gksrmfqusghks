struct JamoPair: Hashable {
  let first: Character
  let second: Character
}

enum DubeolsikTables {
  static let initialJamo: [Character] = [
    "ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ",
    "ㅍ", "ㅎ",
  ]

  static let medialJamo: [Character] = [
    "ㅏ", "ㅐ", "ㅑ", "ㅒ", "ㅓ", "ㅔ", "ㅕ", "ㅖ", "ㅗ", "ㅘ", "ㅙ", "ㅚ", "ㅛ", "ㅜ", "ㅝ", "ㅞ", "ㅟ",
    "ㅠ", "ㅡ", "ㅢ", "ㅣ",
  ]

  static let finalJamo: [Character?] = [
    nil, "ㄱ", "ㄲ", "ㄳ", "ㄴ", "ㄵ", "ㄶ", "ㄷ", "ㄹ", "ㄺ", "ㄻ", "ㄼ", "ㄽ", "ㄾ", "ㄿ", "ㅀ", "ㅁ", "ㅂ",
    "ㅄ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ",
  ]

  static let initialIndex = index(initialJamo)
  static let medialIndex = index(medialJamo)
  static let finalIndex: [Character: Int] = Dictionary(
    uniqueKeysWithValues: finalJamo.enumerated().compactMap { offset, jamo in
      jamo.map { ($0, offset) }
    }
  )

  static let baseKeyToJamo: [Character: Character] = [
    "q": "ㅂ", "w": "ㅈ", "e": "ㄷ", "r": "ㄱ", "t": "ㅅ", "y": "ㅛ", "u": "ㅕ", "i": "ㅑ", "o": "ㅐ",
    "p": "ㅔ", "a": "ㅁ", "s": "ㄴ", "d": "ㅇ", "f": "ㄹ", "g": "ㅎ", "h": "ㅗ", "j": "ㅓ", "k": "ㅏ",
    "l": "ㅣ", "z": "ㅋ", "x": "ㅌ", "c": "ㅊ", "v": "ㅍ", "b": "ㅠ", "n": "ㅜ", "m": "ㅡ",
  ]

  static let shiftedKeyToJamo: [Character: Character] = [
    "q": "ㅃ", "w": "ㅉ", "e": "ㄸ", "r": "ㄲ", "t": "ㅆ", "o": "ㅒ", "p": "ㅖ",
  ]

  static let compoundMedial: [JamoPair: Character] = [
    JamoPair(first: "ㅗ", second: "ㅏ"): "ㅘ",
    JamoPair(first: "ㅗ", second: "ㅐ"): "ㅙ",
    JamoPair(first: "ㅗ", second: "ㅣ"): "ㅚ",
    JamoPair(first: "ㅜ", second: "ㅓ"): "ㅝ",
    JamoPair(first: "ㅜ", second: "ㅔ"): "ㅞ",
    JamoPair(first: "ㅜ", second: "ㅣ"): "ㅟ",
    JamoPair(first: "ㅡ", second: "ㅣ"): "ㅢ",
  ]

  static let compoundFinal: [JamoPair: Character] = [
    JamoPair(first: "ㄱ", second: "ㅅ"): "ㄳ",
    JamoPair(first: "ㄴ", second: "ㅈ"): "ㄵ",
    JamoPair(first: "ㄴ", second: "ㅎ"): "ㄶ",
    JamoPair(first: "ㄹ", second: "ㄱ"): "ㄺ",
    JamoPair(first: "ㄹ", second: "ㅁ"): "ㄻ",
    JamoPair(first: "ㄹ", second: "ㅂ"): "ㄼ",
    JamoPair(first: "ㄹ", second: "ㅅ"): "ㄽ",
    JamoPair(first: "ㄹ", second: "ㅌ"): "ㄾ",
    JamoPair(first: "ㄹ", second: "ㅍ"): "ㄿ",
    JamoPair(first: "ㄹ", second: "ㅎ"): "ㅀ",
    JamoPair(first: "ㅂ", second: "ㅅ"): "ㅄ",
  ]

  static let splitCompoundFinal: [Character: JamoPair] = Dictionary(
    uniqueKeysWithValues: compoundFinal.map { pair, combined in (combined, pair) }
  )

  static let keySequenceByJamo: [Character: String] = [
    "ㄱ": "r", "ㄲ": "R", "ㄳ": "rt", "ㄴ": "s", "ㄵ": "sw", "ㄶ": "sg", "ㄷ": "e", "ㄸ": "E",
    "ㄹ": "f", "ㄺ": "fr", "ㄻ": "fa", "ㄼ": "fq", "ㄽ": "ft", "ㄾ": "fx", "ㄿ": "fv", "ㅀ": "fg",
    "ㅁ": "a", "ㅂ": "q", "ㅃ": "Q", "ㅄ": "qt", "ㅅ": "t", "ㅆ": "T", "ㅇ": "d", "ㅈ": "w",
    "ㅉ": "W", "ㅊ": "c", "ㅋ": "z", "ㅌ": "x", "ㅍ": "v", "ㅎ": "g", "ㅏ": "k", "ㅐ": "o",
    "ㅑ": "i", "ㅒ": "O", "ㅓ": "j", "ㅔ": "p", "ㅕ": "u", "ㅖ": "P", "ㅗ": "h", "ㅘ": "hk",
    "ㅙ": "ho", "ㅚ": "hl", "ㅛ": "y", "ㅜ": "n", "ㅝ": "nj", "ㅞ": "np", "ㅟ": "nl", "ㅠ": "b",
    "ㅡ": "m", "ㅢ": "ml", "ㅣ": "l",
  ]

  static func jamo(for token: PhysicalKeyToken) -> Character? {
    if token.isShifted, let shifted = shiftedKeyToJamo[token.qwertyLetter] {
      return shifted
    }
    return baseKeyToJamo[token.qwertyLetter]
  }

  private static func index(_ characters: [Character]) -> [Character: Int] {
    Dictionary(uniqueKeysWithValues: characters.enumerated().map { ($1, $0) })
  }
}
