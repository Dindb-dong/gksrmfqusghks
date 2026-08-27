import AppKit
import HanKeyPlatformMac
import SwiftUI

struct InstalledApplicationPicker: View {
  let excludedBundleIdentifiers: Set<String>
  let ownBundleIdentifier: String?
  let select: (InstalledApplication) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var applications: [InstalledApplication] = []
  @State private var query = ""
  @State private var isLoading = true

  private let columns = [GridItem(.adaptive(minimum: 104, maximum: 132), spacing: 16)]

  var body: some View {
    NavigationStack {
      Group {
        if isLoading {
          ProgressView("설치된 앱을 찾는 중…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredApplications.isEmpty {
          ContentUnavailableView.search(text: query)
        } else {
          ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
              ForEach(filteredApplications) { application in
                Button {
                  select(application)
                  dismiss()
                } label: {
                  VStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: application.bundleURL.path))
                      .resizable()
                      .scaledToFit()
                      .frame(width: 56, height: 56)
                    Text(application.displayName)
                      .font(.callout)
                      .lineLimit(2)
                      .multilineTextAlignment(.center)
                      .frame(maxWidth: .infinity, minHeight: 34, alignment: .top)
                  }
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(application.displayName) 제외")
              }
            }
            .padding(20)
          }
        }
      }
      .navigationTitle("제외할 앱 선택")
      .searchable(text: $query, placement: .toolbar, prompt: "앱 이름 검색")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("취소") { dismiss() }
        }
      }
    }
    .frame(minWidth: 560, idealWidth: 640, minHeight: 440, idealHeight: 520)
    .task {
      let discovered = await Task.detached(priority: .userInitiated) {
        InstalledApplicationCatalog.discover()
      }.value
      applications = discovered
      isLoading = false
    }
  }

  private var filteredApplications: [InstalledApplication] {
    applications.filter { application in
      application.bundleIdentifier != ownBundleIdentifier
        && !excludedBundleIdentifiers.contains(application.bundleIdentifier)
        && (query.isEmpty
          || application.displayName.localizedCaseInsensitiveContains(query))
    }
  }
}

struct ExcludedApplicationLabel: View {
  let bundleIdentifier: String

  var body: some View {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
      HStack(spacing: 10) {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
          .resizable()
          .scaledToFit()
          .frame(width: 28, height: 28)
        Text(applicationName(at: url))
      }
    } else {
      Label("설치되지 않은 앱", systemImage: "app.dashed")
        .foregroundStyle(.secondary)
    }
  }

  private func applicationName(at url: URL) -> String {
    let bundle = Bundle(url: url)
    return (bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
      ?? (bundle?.localizedInfoDictionary?["CFBundleName"] as? String)
      ?? url.deletingPathExtension().lastPathComponent
  }
}
