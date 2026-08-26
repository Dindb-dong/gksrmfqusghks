import HanKeyCore
import SwiftUI

@main
struct HanKeyApplication: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var model = AppModel.shared

  var body: some Scene {
    MenuBarExtra(HanKeyCoreMetadata.displayName, systemImage: model.operationalStatus.symbol) {
      MenuBarContent(model: model)
    }

    Window("한글변환 시작하기", id: "onboarding") {
      OnboardingView(model: model, onFinish: {})
    }
    .defaultSize(width: 640, height: 520)
    .windowResizability(.contentSize)

    Settings {
      SettingsView(model: model)
    }
  }
}
