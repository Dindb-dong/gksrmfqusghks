import Carbon.HIToolbox
import CoreGraphics
import Foundation
import XCTest

@testable import HanKeyPlatformMac

final class NativeInputSourceSwitchTests: XCTestCase {
  private var sources: [String] {
    [InputSourceController.abcIdentifier, InputSourceController.korean2SetIdentifier]
  }
  private var hotkeys: [String: Any] {
    ["60": ["enabled": true, "value": ["type": "standard", "parameters": [32, 49, 262144]]]]
  }

  func testCancellationAndShutdownBeforeFirstHandoffDoNotCreateTap() {
    let store = InputHandoffGateStore(makeGate: {
      XCTFail("Cancellation created a global event tap")
      fatalError("Unexpected tap construction")
    })
    store.cancelActive(for: .applicationChanged)
    store.shutdown()
  }

  func testOnlyUnambiguousConfiguredTwoSourceSwitchIsEligible() {
    XCTAssertTrue(
      NativeInputSourceSwitch.configurationIsSupported(
        hotkeys: hotkeys, enabledIdentifiers: sources))
    for identifiers in [[], [sources[0]], sources + ["other"], sources + [sources[0]]] {
      XCTAssertFalse(
        NativeInputSourceSwitch.configurationIsSupported(
          hotkeys: hotkeys, enabledIdentifiers: identifiers))
    }
    for configuration: [String: Any]? in [
      nil, [:],
      ["60": ["enabled": false, "value": ["type": "standard", "parameters": [32, 49, 262144]]]],
      ["60": ["enabled": true, "value": ["type": "standard", "parameters": [32, 49, 786432]]]],
      ["60": ["enabled": true, "value": ["type": "standard", "parameters": [0, 0, 262144]]]],
    ] {
      XCTAssertFalse(
        NativeInputSourceSwitch.configurationIsSupported(
          hotkeys: configuration, enabledIdentifiers: sources))
    }
  }

  func testPreparesBalancedPrivateMarkedChordBeforeAnyDispatch() throws {
    let native = try XCTUnwrap(NativeInputSourceSwitch())
    XCTAssertEqual(native.events.map(\.type), [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
    XCTAssertEqual(
      native.events.map { $0.getIntegerValueField(.keyboardEventKeycode) },
      [Int64(kVK_Control), Int64(kVK_Space), Int64(kVK_Space), Int64(kVK_Control)])
    XCTAssertEqual(
      native.events.map { $0.flags.rawValue },
      [
        CGEventFlags.maskControl.rawValue, CGEventFlags.maskControl.rawValue,
        CGEventFlags.maskControl.rawValue, 0,
      ])
    XCTAssertTrue(native.events.allSatisfy(HanKeySyntheticEvent.isMarked))
  }
}
