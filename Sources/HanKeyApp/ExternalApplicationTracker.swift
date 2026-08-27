import AppKit

@MainActor
final class ExternalApplicationTracker: NSObject {
  private let ownBundleIdentifier: String?
  private(set) var lastExternalBundleIdentifier: String?

  init(ownBundleIdentifier: String?) {
    self.ownBundleIdentifier = ownBundleIdentifier
    super.init()
    capture(NSWorkspace.shared.frontmostApplication)
    NSWorkspace.shared.notificationCenter.addObserver(
      self,
      selector: #selector(applicationDidActivate(_:)),
      name: NSWorkspace.didActivateApplicationNotification,
      object: nil
    )
  }

  @objc private func applicationDidActivate(_ notification: Notification) {
    capture(notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
  }

  private func capture(_ application: NSRunningApplication?) {
    guard
      let bundleIdentifier = application?.bundleIdentifier,
      bundleIdentifier != ownBundleIdentifier
    else {
      return
    }
    lastExternalBundleIdentifier = bundleIdentifier
  }
}
