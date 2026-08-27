public enum WordBoundary: String, Equatable, Sendable {
  case space
  case returnKey
  case tab
  case punctuation
}

public enum BufferInvalidationReason: String, Equatable, Sendable {
  case applicationChanged
  case focusChanged
  case pointerInteraction
  case navigation
  case modifiedCommand
  case inputSourceChanged
  case systemStateChanged
  case unknownKey
  case idleTimeout
  case capacityExceeded
  case secureInput
  case stopped
}

public enum BufferObservation: Equatable, Sendable {
  case printable(PhysicalKeyToken)
  case commandPrefixSymbol(CommandPrefixSymbol)
  case deleteBackward(BackwardDeletionKind)
  case boundary(WordBoundary)
  case invalidate(BufferInvalidationReason)
  case protectionChanged(isProtected: Bool)
}

public enum CommandPrefixSymbol: String, Equatable, Sendable {
  case slash
  case hyphen
}

public enum LeadingCommandPrefix: String, Equatable, Sendable {
  case slash
  case singleHyphen
  case doubleHyphen
}

public enum BackwardDeletionKind: String, Equatable, Sendable {
  case character
  case word
  case line
}

public struct BufferedWord: Equatable, Sendable {
  public let tokens: [PhysicalKeyToken]
  public let leadingCommandPrefix: LeadingCommandPrefix?

  public init(
    tokens: [PhysicalKeyToken],
    leadingCommandPrefix: LeadingCommandPrefix? = nil
  ) {
    self.tokens = tokens
    self.leadingCommandPrefix = leadingCommandPrefix
  }

  public var qwerty: String {
    String(tokens.map(\.ascii))
  }
}

public enum WordBufferAction: Equatable, Sendable {
  case none
  case completed(BufferedWord, boundary: WordBoundary)
  case purged(BufferInvalidationReason)
  case ignoredWhileProtected
}

public struct WordBuffer: Sendable {
  public let maximumTokenCount: Int
  public let idleTimeoutNanoseconds: UInt64

  public private(set) var isProtected = false
  public private(set) var tokens: [PhysicalKeyToken] = []
  public private(set) var leadingCommandPrefix: LeadingCommandPrefix?
  private var lastActivityNanoseconds: UInt64?

  public init(
    maximumTokenCount: Int = 64,
    idleTimeoutNanoseconds: UInt64 = 10_000_000_000
  ) {
    precondition(maximumTokenCount > 0)
    precondition(idleTimeoutNanoseconds > 0)
    self.maximumTokenCount = maximumTokenCount
    self.idleTimeoutNanoseconds = idleTimeoutNanoseconds
    tokens.reserveCapacity(maximumTokenCount)
  }

  public mutating func handle(
    _ observation: BufferObservation,
    at timestampNanoseconds: UInt64
  ) -> WordBufferAction {
    if case .protectionChanged(let shouldProtect) = observation {
      if shouldProtect {
        purge()
        isProtected = true
        return .purged(.secureInput)
      }
      isProtected = false
      return .none
    }

    guard !isProtected else {
      return .ignoredWhileProtected
    }

    let expired = hasExpired(at: timestampNanoseconds)
    if expired {
      purge()
    }

    switch observation {
    case .printable(let token):
      tokens.append(token)
      lastActivityNanoseconds = timestampNanoseconds
      if tokens.count > maximumTokenCount {
        purge()
        return .purged(.capacityExceeded)
      }
      return expired ? .purged(.idleTimeout) : .none

    case .commandPrefixSymbol(let symbol):
      if !tokens.isEmpty {
        let word = BufferedWord(
          tokens: tokens,
          leadingCommandPrefix: leadingCommandPrefix
        )
        purge()
        return .completed(word, boundary: .punctuation)
      }

      switch (leadingCommandPrefix, symbol) {
      case (nil, .slash):
        leadingCommandPrefix = .slash
      case (nil, .hyphen):
        leadingCommandPrefix = .singleHyphen
      case (.singleHyphen, .hyphen):
        leadingCommandPrefix = .doubleHyphen
      default:
        purge()
        return .purged(.unknownKey)
      }
      lastActivityNanoseconds = timestampNanoseconds
      return expired ? .purged(.idleTimeout) : .none

    case .deleteBackward(let kind):
      if kind == .character {
        if !tokens.isEmpty {
          tokens.removeLast()
        } else {
          leadingCommandPrefix = nil
        }
      } else {
        purge()
        return .purged(.modifiedCommand)
      }
      lastActivityNanoseconds =
        tokens.isEmpty && leadingCommandPrefix == nil ? nil : timestampNanoseconds
      return expired ? .purged(.idleTimeout) : .none

    case .boundary(let boundary):
      guard !expired, !tokens.isEmpty else {
        if leadingCommandPrefix != nil {
          purge()
        }
        return expired ? .purged(.idleTimeout) : .none
      }
      let word = BufferedWord(
        tokens: tokens,
        leadingCommandPrefix: leadingCommandPrefix
      )
      purge()
      return .completed(word, boundary: boundary)

    case .invalidate(let reason):
      let hadContent = !tokens.isEmpty || leadingCommandPrefix != nil
      purge()
      return hadContent || reason == .stopped ? .purged(reason) : .none

    case .protectionChanged:
      return .none
    }
  }

  private func hasExpired(at timestampNanoseconds: UInt64) -> Bool {
    guard let lastActivityNanoseconds, timestampNanoseconds >= lastActivityNanoseconds else {
      return false
    }
    return timestampNanoseconds - lastActivityNanoseconds >= idleTimeoutNanoseconds
  }

  private mutating func purge() {
    tokens.removeAll(keepingCapacity: true)
    leadingCommandPrefix = nil
    lastActivityNanoseconds = nil
  }
}
