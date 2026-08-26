import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var onboardingWindowController: NSWindowController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--dark-appearance") {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
      }
      if ProcessInfo.processInfo.arguments.contains("--show-settings") {
        showDebugSettings()
        return
      }
    #endif
    guard !UserDefaults.standard.bool(forKey: "onboardingCompleted") else {
      AppModel.shared.resumeSavedCorrectionIfPossible()
      return
    }
    showInitialOnboarding()
  }

  private func showInitialOnboarding() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = "한글변환 시작하기"
    window.isReleasedWhenClosed = false
    window.contentViewController = NSHostingController(
      rootView: OnboardingView(model: AppModel.shared) { [weak self] in
        self?.onboardingWindowController?.close()
      }
    )
    window.center()

    let controller = NSWindowController(window: window)
    onboardingWindowController = controller
    controller.showWindow(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }

  #if DEBUG
    private func showDebugSettings() {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 620, height: 500),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
      )
      window.title = "한글변환 설정"
      window.isReleasedWhenClosed = false
      window.contentViewController = NSHostingController(
        rootView: SettingsView(model: AppModel.shared))
      window.center()
      let controller = NSWindowController(window: window)
      onboardingWindowController = controller
      controller.showWindow(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
    }
  #endif
}
