import AppKit
import SwiftUI

@MainActor
enum SettingsWindowPresenter {
  private static weak var settingsWindow: NSWindow?

  static func register(_ window: NSWindow) {
    settingsWindow = window
  }

  static func open(_ openSettings: () -> Void) {
    NSApplication.shared.activate(ignoringOtherApps: true)
    openSettings()

    Task { @MainActor in
      for attempt in 0..<6 {
        if let window = settingsWindow {
          bringToFront(window)
          return
        }
        if attempt < 5 {
          try? await Task.sleep(for: .milliseconds(40))
        }
      }
    }
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
