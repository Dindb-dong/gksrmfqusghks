@testable import HanKeyPlatformMac

@MainActor
final class TestInputHandoff: InputHandoffControlling {
  var isValid = true
  private(set) var finishCount = 0
  func finish() { finishCount += 1 }
}
