import AppKit
import SwiftUI

@MainActor
enum SettingsWindowPresenter {
  private static weak var settingsWindow: NSWindow?
  private static var shouldBringNextRegisteredWindowToFront = false

  static func register(_ window: NSWindow) {
    settingsWindow = window
    guard shouldBringNextRegisteredWindowToFront else { return }
    shouldBringNextRegisteredWindowToFront = false
    bringToFront(window)
  }

  static func open(_ openSettings: () -> Void) {
    shouldBringNextRegisteredWindowToFront = true
    NSApplication.shared.activate(ignoringOtherApps: true)
    openSettings()

    guard let settingsWindow else { return }
    shouldBringNextRegisteredWindowToFront = false
    bringToFront(settingsWindow)
  }

  private static func bringToFront(_ window: NSWindow) {
    if !window.collectionBehavior.contains(.canJoinAllSpaces) {
      window.collectionBehavior.insert(.moveToActiveSpace)
    }
    NSApplication.shared.activate(ignoringOtherApps: true)
    window.orderFrontRegardless()
    window.makeKeyAndOrderFront(nil)
  }
}

struct SettingsWindowBridge: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    SettingsWindowTrackingView()
  }

  func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
private final class SettingsWindowTrackingView: NSView {
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard let window else { return }
    SettingsWindowPresenter.register(window)
  }
}
