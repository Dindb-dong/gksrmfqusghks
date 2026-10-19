import AppKit
import ApplicationServices
import Carbon.HIToolbox
import HanKeyCore
import HanKeyPlatformMac

@MainActor
final class Fixture: NSObject, NSApplicationDelegate {
  var window: NSWindow!
  let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 240))
  let sources = InputSourceController()
  let rewriter = FocusedTextRewriter()

  func applicationDidFinishLaunching(_ notification: Notification) {
    window = NSWindow(
      contentRect: NSRect(x: 100, y: 100, width: 600, height: 240),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "HanKey isolated synthetic input fixture"
    window.contentView = textView
    textView.isRichText = false
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(textView)
    NSApplication.shared.activate(ignoringOtherApps: true)
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(300))
      let success = await runChecks()
      window.close()
      exit(success ? 0 : 1)
    }
  }

  func runChecks() async -> Bool {
    guard AXIsProcessTrusted() else {
      print("SKIP existing Accessibility permission unavailable")
      return false
    }
    guard let initialSource = sources.currentSource() else {
      print("SKIP source unavailable")
      return false
    }
    defer {
      if NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() {
        _ = sources.select(language: initialSource.language)
      }
    }
    for (original, replacement, target) in [
      ("gksrmffh", "한글로", TokenLanguage.korean),
      ("ㅡ먀ㅜ", "main", TokenLanguage.english),
    ] {
      guard sources.select(language: target.opposite) != nil else {
        print("FAIL source setup")
        return false
      }
      textView.string = original + " "
      textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
      window.makeFirstResponder(textView)
      guard let snapshot = rewriter.currentSnapshot(), snapshot.identity.processID == getpid()
      else {
        print("SKIP fixture focus unavailable")
        return false
      }
      let coordinator = CorrectionTransactionCoordinator()
      let result = await coordinator.perform(
        proposal: CorrectionProposal(
          original: original, replacement: replacement, targetLanguage: target,
          confidence: 1, usedExplicitRule: false), boundary: .space,
        expectedFocus: snapshot.identity)
      guard case .corrected = result, textView.string == replacement + " ",
        textView.selectedRange() == NSRange(location: replacement.utf16.count + 1, length: 0)
      else {
        switch result {
        case .corrected:
          print(
            "FAIL native text/caret", textView.string.utf16.count,
            textView.selectedRange().location, textView.selectedRange().length)
        case .cancelled(.replacementUnverified):
          print(
            "FAIL native verification", textView.string.utf16.count,
            textView.selectedRange().location, textView.selectedRange().length)
        case .cancelled(.replacementRejected): print("FAIL native AX rejection")
        case .cancelled(.sourceChanged): print("FAIL native source changed")
        case .cancelled(.sourceSwitchFailed): print("FAIL native source switch")
        default: print("FAIL native preflight")
        }
        return false
      }
      for key in [CGKeyCode(kVK_ANSI_R), CGKeyCode(kVK_ANSI_K), CGKeyCode(kVK_Space)] {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
          let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)!
          event.flags = []
          event.postToPid(getpid())
        }
      }
      try? await Task.sleep(for: .milliseconds(100))
      let expected = replacement + " " + (target == .korean ? "가 " : "rk ")
      guard textView.string == expected else {
        print("FAIL effective IME activation")
        return false
      }
      print(
        target == .korean
          ? "PASS native English-to-Korean + next Korean keys"
          : "PASS native Korean-to-English + next English keys")
    }
    return true
  }
}

@main
struct Main {
  @MainActor static func main() {
    let app = NSApplication.shared
    let delegate = Fixture()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
    _ = delegate
  }
}
