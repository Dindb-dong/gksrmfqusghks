import AppKit
import HanKeyCore
import HanKeyPlatformMac
import Observation

enum OperationalStatus: Equatable {
  case active
  case paused
  case permissionRequired
  case protected
  case eventTapError

  var title: String {
    switch self {
    case .active: "자동 교정 켜짐"
    case .paused: "자동 교정 일시정지"
    case .permissionRequired: "권한 설정 필요"
    case .protected: "보안 입력 보호 중"
    case .eventTapError: "입력 관찰을 시작할 수 없음"
    }
  }

  var detail: String {
    switch self {
    case .active: "고신뢰 단어만 로컬에서 교정합니다."
    case .paused: "키 입력을 관찰하지 않습니다."
    case .permissionRequired: "입력 모니터링과 손쉬운 사용 권한을 확인하세요."
    case .protected: "현재 입력은 관찰·교정·저장하지 않습니다."
    case .eventTapError: "자동 교정은 중지됐습니다. 권한을 확인한 뒤 다시 시도하세요."
    }
  }

  var symbol: String {
    switch self {
    case .active: "character.cursor.ibeam"
    case .paused: "pause.circle"
    case .permissionRequired: "exclamationmark.shield"
    case .protected: "lock.shield"
    case .eventTapError: "exclamationmark.triangle"
    }
  }
}

enum CorrectionActivity: Equatable {
  case idle
  case checking
  case corrected
  case sourceSwitchFailed

  var title: String {
    switch self {
    case .idle: "대기 중"
    case .checking: "교정 확인 중"
    case .corrected: "최근 교정 완료"
    case .sourceSwitchFailed: "입력 소스 전환 실패"
    }
  }
}

@MainActor
@Observable
final class AppModel {
  static let shared = AppModel()

  private(set) var permissions = PlatformCapabilities.currentPermissionSnapshot()
  private(set) var isCorrectionEnabled = false
  private(set) var observationState: InputObservationState = .stopped
  private(set) var correctionActivity: CorrectionActivity = .idle
  @ObservationIgnored private var observationRuntime: InputObservationRuntime?
  @ObservationIgnored private var inputSourceController: InputSourceController?
  @ObservationIgnored private var transactionCoordinator: CorrectionTransactionCoordinator?
  @ObservationIgnored private var activeTransaction: Task<Void, Never>?
  @ObservationIgnored private var lastCorrectionRecord: CorrectionTransactionRecord?

  init() {
    let inputSourceController = InputSourceController()
    self.inputSourceController = inputSourceController
    transactionCoordinator = CorrectionTransactionCoordinator(inputSources: inputSourceController)
    observationRuntime = InputObservationRuntime { [weak self] event in
      self?.handleRuntimeEvent(event)
    }
  }

  var operationalStatus: OperationalStatus {
    if permissions.isSecureInputEnabled || observationState == .protected {
      return .protected
    }
    if observationState == .tapUnavailable {
      return .eventTapError
    }
    if !permissions.hasRequiredPermissions || observationState == .permissionRequired {
      return .permissionRequired
    }
    return isCorrectionEnabled ? .active : .paused
  }

  func refreshPermissions() {
    permissions = PlatformCapabilities.currentPermissionSnapshot()
  }

  func setCorrectionEnabled(_ enabled: Bool) {
    guard enabled != isCorrectionEnabled else {
      return
    }
    if enabled {
      refreshPermissions()
      guard observationRuntime?.start() == true else {
        isCorrectionEnabled = false
        return
      }
      isCorrectionEnabled = true
    } else {
      observationRuntime?.stop()
      activeTransaction?.cancel()
      activeTransaction = nil
      isCorrectionEnabled = false
      correctionActivity = .idle
    }
  }

  func requestInputMonitoring() {
    PermissionController.requestInputMonitoring()
    refreshPermissions()
  }

  func requestAccessibility() {
    PermissionController.requestAccessibility()
    refreshPermissions()
  }

  func openInputMonitoringSettings() {
    openSystemSettings(anchor: "Privacy_ListenEvent")
  }

  func openAccessibilitySettings() {
    openSystemSettings(anchor: "Privacy_Accessibility")
  }

  private func openSystemSettings(anchor: String) {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
      )
    else {
      return
    }
    NSWorkspace.shared.open(url)
  }

  private func handleRuntimeEvent(_ event: InputObservationRuntimeEvent) {
    switch event {
    case .stateChanged(let state):
      observationState = state
      refreshPermissions()
    case .wordCompleted(let word, let boundary, let focusIdentity):
      evaluateAndCorrect(word: word, boundary: boundary, focusIdentity: focusIdentity)
    }
  }

  private func evaluateAndCorrect(
    word: BufferedWord,
    boundary: WordBoundary,
    focusIdentity: FocusedElementIdentity
  ) {
    guard
      activeTransaction == nil,
      let activeLanguage = inputSourceController?.currentSource()?.language,
      let transactionCoordinator
    else {
      return
    }
    let original: String
    let candidate: String
    switch activeLanguage {
    case .english:
      original = word.qwerty
      candidate = DubeolsikConverter.compose(word.qwerty)
    case .korean:
      original = DubeolsikConverter.compose(word.qwerty)
      candidate = DubeolsikConverter.decomposeToQWERTY(original)
    }
    let evidence = SystemLexiconEvidenceProvider.evidence(
      original: original,
      candidate: candidate,
      activeLanguage: activeLanguage
    )
    let decision = CorrectionDecisionEngine().decide(
      CorrectionRequest(
        token: original,
        activeLanguage: activeLanguage,
        lexiconEvidence: evidence
      )
    )
    guard case .correct(let proposal) = decision else {
      return
    }

    correctionActivity = .checking
    activeTransaction = Task { @MainActor [weak self] in
      let result = await transactionCoordinator.perform(
        proposal: proposal,
        boundary: boundary,
        expectedFocus: focusIdentity
      )
      guard let self else {
        return
      }
      switch result {
      case .corrected(let record):
        lastCorrectionRecord = record
        correctionActivity = .corrected
        if UserDefaults.standard.object(forKey: "showCorrectionFeedback") == nil
          || UserDefaults.standard.bool(forKey: "showCorrectionFeedback")
        {
          NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [.announcement: "한영 입력 교정을 완료했습니다."]
          )
        }
      case .cancelled(.sourceSwitchFailed(let record)):
        lastCorrectionRecord = record
        correctionActivity = .sourceSwitchFailed
      case .cancelled:
        correctionActivity = .idle
      }
      activeTransaction = nil
    }
  }
}
