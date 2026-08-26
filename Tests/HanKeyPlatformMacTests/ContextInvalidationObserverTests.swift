import AppKit
import HanKeyCore
import XCTest

@testable import HanKeyPlatformMac

@MainActor
final class ContextInvalidationObserverTests: XCTestCase {
  func testSleepWakeAndSessionTransitionsInvalidateBufferedState() async {
    var reasons: [BufferInvalidationReason] = []
    let observer = ContextInvalidationObserver { reason in
      MainActor.assumeIsolated {
        reasons.append(reason)
      }
    }
    observer.start()
    defer { observer.stop() }

    let center = NSWorkspace.shared.notificationCenter
    center.post(name: NSWorkspace.willSleepNotification, object: nil)
    center.post(name: NSWorkspace.didWakeNotification, object: nil)
    center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
    await Task.yield()

    XCTAssertEqual(reasons, [.systemStateChanged, .systemStateChanged, .systemStateChanged])
  }
}
