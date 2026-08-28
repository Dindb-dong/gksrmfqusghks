import HanKeyCore
import Observation
import Sparkle

@MainActor
@Observable
final class SoftwareUpdateController {
  private(set) var isConfigured: Bool
  private(set) var automaticallyChecksForUpdates: Bool
  private(set) var status: String

  @ObservationIgnored private var controller: SPUStandardUpdaterController?

  init(bundle: Bundle = .main) {
    let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
    let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
    let isConfigured = SoftwareUpdateConfiguration(
      feedURLString: feedURL,
      publicEDKey: publicKey
    ) != nil
    self.isConfigured = isConfigured
    automaticallyChecksForUpdates =
      bundle.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool ?? true
    status = isConfigured ? "업데이트 서비스를 시작할 준비가 됐습니다." : "이 빌드에는 업데이트 피드가 없습니다."
  }

  func start() {
    guard isConfigured, controller == nil else { return }
    let controller = SPUStandardUpdaterController(
      startingUpdater: false,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
    self.controller = controller
    controller.startUpdater()
    automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
    updateStatus()
  }

  func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
    guard isConfigured else { return }
    start()
    controller?.updater.automaticallyChecksForUpdates = enabled
    automaticallyChecksForUpdates = enabled
    updateStatus()
  }

  func checkForUpdates() {
    guard isConfigured else {
      status = "공개 HTTPS 피드와 Sparkle 서명 키를 확인하세요."
      return
    }
    start()
    controller?.checkForUpdates(nil)
  }

  private func updateStatus() {
    status =
      automaticallyChecksForUpdates
      ? "앱 실행 시와 이후 최대 24시간마다 새 버전을 확인합니다."
      : "자동 확인이 꺼져 있습니다."
  }
}
