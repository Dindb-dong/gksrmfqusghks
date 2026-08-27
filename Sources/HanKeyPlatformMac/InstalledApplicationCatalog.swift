import Foundation

public struct InstalledApplication: Identifiable, Hashable, Sendable {
  public let bundleIdentifier: String
  public let displayName: String
  public let bundleURL: URL

  public var id: String { bundleIdentifier }

  public init(bundleIdentifier: String, displayName: String, bundleURL: URL) {
    self.bundleIdentifier = bundleIdentifier
    self.displayName = displayName
    self.bundleURL = bundleURL
  }
}

public enum InstalledApplicationCatalog {
  public static func discover(
    roots: [URL] = defaultRoots,
    fileManager: FileManager = .default
  ) -> [InstalledApplication] {
    var applicationsByIdentifier: [String: InstalledApplication] = [:]

    for root in roots where fileManager.fileExists(atPath: root.path) {
      guard
        let enumerator = fileManager.enumerator(
          at: root,
          includingPropertiesForKeys: [.isApplicationKey, .isDirectoryKey],
          options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
      else { continue }

      for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
        guard
          let bundle = Bundle(url: url),
          let bundleIdentifier = bundle.bundleIdentifier?.trimmingCharacters(in: .whitespaces),
          !bundleIdentifier.isEmpty
        else { continue }

        let displayName =
          (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
          ?? (bundle.localizedInfoDictionary?["CFBundleName"] as? String)
          ?? (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
          ?? (bundle.infoDictionary?["CFBundleName"] as? String)
          ?? url.deletingPathExtension().lastPathComponent
        let application = InstalledApplication(
          bundleIdentifier: bundleIdentifier,
          displayName: displayName,
          bundleURL: url
        )
        if applicationsByIdentifier[bundleIdentifier] == nil {
          applicationsByIdentifier[bundleIdentifier] = application
        }
      }
    }

    return applicationsByIdentifier.values.sorted {
      $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
    }
  }

  public static var defaultRoots: [URL] {
    var roots = [
      URL(fileURLWithPath: "/Applications", isDirectory: true),
      URL(fileURLWithPath: "/System/Applications", isDirectory: true),
    ]
    let userApplications = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Applications", isDirectory: true)
    roots.append(userApplications)
    return roots
  }
}
