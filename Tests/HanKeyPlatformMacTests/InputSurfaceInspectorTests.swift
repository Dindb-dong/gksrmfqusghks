import ApplicationServices
import HanKeyCore
import XCTest

@testable import HanKeyPlatformMac

final class InputSurfaceInspectorTests: XCTestCase {
  func testSecureAndUnknownContextsFailClosed() {
    let field = AccessibilityElementDescriptor(role: kAXTextFieldRole as String, subrole: nil)
    XCTAssertEqual(
      InputSurfaceInspector.classify(
        bundleIdentifier: "com.apple.TextEdit",
        descriptor: field,
        securityState: .secure
      ),
      .secureTextField
    )
    XCTAssertEqual(
      InputSurfaceInspector.classify(
        bundleIdentifier: nil,
        descriptor: field,
        securityState: .editable
      ),
      .unsupported
    )
  }

  func testProtectedApplicationFamiliesAreClassifiedBeforeMutation() {
    let field = AccessibilityElementDescriptor(role: kAXTextAreaRole as String, subrole: nil)
    let fixtures: [(String, InputSurface)] = [
      ("com.apple.Terminal", .terminal),
      ("com.microsoft.VSCode", .ide),
      ("com.jetbrains.intellij.ce", .ide),
      ("com.1password.1password", .passwordManager),
      ("com.microsoft.rdc.macos", .remoteDesktop),
      ("com.vmware.fusion", .remoteDesktop),
    ]
    for (bundleIdentifier, expected) in fixtures {
      XCTAssertEqual(
        InputSurfaceInspector.classify(
          bundleIdentifier: bundleIdentifier,
          descriptor: field,
          securityState: .editable
        ),
        expected,
        bundleIdentifier
      )
    }
  }

  func testBrowserAddressChromeIsProtectedButPageFieldsRemainStandard() {
    let addressField = AccessibilityElementDescriptor(
      role: kAXTextFieldRole as String,
      subrole: nil,
      identifier: "Address and Search",
      roleDescription: "smart search field"
    )
    XCTAssertEqual(
      InputSurfaceInspector.classify(
        bundleIdentifier: "com.apple.Safari",
        descriptor: addressField,
        securityState: .editable
      ),
      .browserAddressBar
    )

    let pageField = AccessibilityElementDescriptor(
      role: kAXTextAreaRole as String,
      subrole: nil,
      identifier: "message-body",
      roleDescription: "text area"
    )
    XCTAssertEqual(
      InputSurfaceInspector.classify(
        bundleIdentifier: "com.google.Chrome",
        descriptor: pageField,
        securityState: .editable
      ),
      .standardText
    )
  }

  func testOrdinaryNativeEditorRemainsSupported() {
    XCTAssertEqual(
      InputSurfaceInspector.classify(
        bundleIdentifier: "com.apple.TextEdit",
        descriptor: AccessibilityElementDescriptor(
          role: kAXTextAreaRole as String,
          subrole: nil
        ),
        securityState: .editable
      ),
      .standardText
    )
  }

  func testUserExclusionProtectsOtherwiseStandardField() {
    let context = FocusedElementContext(
      state: .editable,
      identity: FocusedElementIdentity(processID: 1, elementHash: 1),
      surface: .standardText,
      bundleIdentifier: "com.example.PrivateEditor"
    )

    XCTAssertTrue(
      InputProtectionPolicy.mustProtect(
        secureInput: false,
        focusedContext: context,
        isApplicationExcluded: true
      )
    )
    XCTAssertFalse(
      InputProtectionPolicy.mustProtect(
        secureInput: false,
        focusedContext: context,
        isApplicationExcluded: false
      )
    )
  }
}
