/// Volatile FIFO ownership for a bounded input handoff. Callers serialize access.
public struct InputHandoffBuffer<Event> {
  public enum Disposition {
    case buffered
    case pass(prefix: [Event])
  }

  private enum Phase {
    case idle
    case holding(until: UInt64)
    case releasing
  }

  private var phase: Phase = .idle
  private var events: [Event] = []
  private var generation: UInt64 = 0
  private let maximumCount: Int
  public var count: Int { events.count }
  public static var durationNanoseconds: UInt64 { 80_000_000 }

  public init(maximumCount: Int = 256) {
    precondition(maximumCount > 0)
    self.maximumCount = maximumCount
  }

  public mutating func begin(now: UInt64) -> UInt64? {
    guard case .idle = phase else { return nil }
    generation &+= 1
    phase = .holding(until: now + Self.durationNanoseconds)
    return generation
  }

  public func isValid(_ token: UInt64, now: UInt64, reserve: UInt64 = 15_000_000) -> Bool {
    guard token == generation, case .holding(let deadline) = phase else { return false }
    return now + reserve < deadline
  }

  public func needsDrain(now: UInt64) -> Bool {
    switch phase {
    case .idle: false
    case .holding(let deadline): now >= deadline
    case .releasing: true
    }
  }

  public mutating func receive(now: UInt64, copy: () -> Event?) -> Disposition {
    if case .holding(let deadline) = phase, now < deadline,
      events.count < maximumCount, let event = copy()
    {
      events.append(event)
      return .buffered
    }
    return .pass(prefix: drain())
  }

  @discardableResult
  public mutating func requestRelease(_ token: UInt64) -> Bool {
    guard token == generation else { return false }
    guard case .idle = phase else {
      phase = events.isEmpty ? .idle : .releasing
      return !events.isEmpty
    }
    return false
  }

  @discardableResult
  public mutating func expire(_ token: UInt64, now: UInt64) -> Bool {
    guard token == generation, needsDrain(now: now) else { return false }
    return requestRelease(token)
  }

  public mutating func drain() -> [Event] {
    let pending = events
    events.removeAll(keepingCapacity: true)
    phase = .idle
    return pending
  }
}
