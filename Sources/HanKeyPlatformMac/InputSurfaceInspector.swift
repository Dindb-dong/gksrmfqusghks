import HanKeyCore

public enum InputSurfaceInspector {
  public static func classify(
    bundleIdentifier: String?,
    descriptor: AccessibilityElementDescriptor,
    securityState: FocusedElementSecurityState
  ) -> InputSurface {
    if securityState == .secure {
      return .secureTextField
    }
    guard securityState == .editable, let bundleIdentifier else {
      return .unsupported
    }

    let normalizedBundle = bundleIdentifier.lowercased()
    if matches(normalizedBundle, exact: passwordManagers, prefixes: passwordManagerPrefixes) {
      return .passwordManager
    }
    if matches(normalizedBundle, exact: terminals, prefixes: terminalPrefixes) {
      return .terminal
    }
    if matches(normalizedBundle, exact: ides, prefixes: idePrefixes) {
      return .ide
    }
    if matches(normalizedBundle, exact: remoteDesktops, prefixes: remoteDesktopPrefixes) {
      return .remoteDesktop
    }
    if browsers.contains(normalizedBundle), looksLikeBrowserChrome(descriptor) {
      return .browserAddressBar
    }
    return .standardText
  }

  private static func looksLikeBrowserChrome(_ descriptor: AccessibilityElementDescriptor) -> Bool {
    let signals = [descriptor.identifier, descriptor.roleDescription]
      .compactMap { $0?.lowercased() }
      .joined(separator: " ")
    let protectedTerms = [
      "address", "location", "omnibox", "urlbar", "smart search", "website name",
    ]
    return protectedTerms.contains { signals.contains($0) }
  }

  private static func matches(
    _ bundleIdentifier: String,
    exact: Set<String>,
    prefixes: [String]
  ) -> Bool {
    exact.contains(bundleIdentifier) || prefixes.contains { bundleIdentifier.hasPrefix($0) }
  }

  private static let browsers: Set<String> = [
    "com.apple.safari", "com.google.chrome", "com.google.chrome.beta",
    "com.microsoft.edgemac", "company.thebrowser.browser", "org.mozilla.firefox",
  ]
  private static let terminals: Set<String> = [
    "com.apple.terminal", "com.cmuxterm.app", "com.googlecode.iterm2", "dev.warp.warp-stable",
    "io.alacritty", "net.kovidgoyal.kitty",
  ]
  private static let terminalPrefixes = ["com.mitchellh.ghostty"]
  private static let ides: Set<String> = [
    "com.apple.dt.xcode", "com.microsoft.vscode", "com.jetbrains.intellij",
    "com.jetbrains.appcode", "com.sublimetext.4",
  ]
  private static let idePrefixes = ["com.jetbrains.", "com.microsoft.vscode"]
  private static let passwordManagers: Set<String> = [
    "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
    "com.lastpass.lastpass", "com.dashlane.dashlanephonefinal",
  ]
  private static let passwordManagerPrefixes = ["com.1password.", "com.agilebits."]
  private static let remoteDesktops: Set<String> = [
    "com.microsoft.rdc.macos", "com.teamviewer.teamviewer", "com.anydesk.anydesk",
    "com.apple.screensharing", "com.parallels.desktop.console",
  ]
  private static let remoteDesktopPrefixes = ["com.citrix.", "com.vmware."]
}
