import AppKit
import HanKeyCore
import HanKeyPlatformMac
import Observation
import UniformTypeIdentifiers

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

  var diagnosticCode: String {
    switch self {
    case .active: "active"
    case .paused: "paused"
    case .permissionRequired: "permission_required"
    case .protected: "protected"
    case .eventTapError: "event_tap_error"
    }
  }
}

enum CorrectionActivity: Equatable {
  case idle
  case checking
  case corrected
  case sourceSwitchFailed
  case manuallyCorrected
  case undone
  case repeatedInputPreserved
  case actionUnavailable

  var title: String {
    switch self {
    case .idle: "대기 중"
    case .checking: "교정 확인 중"
    case .corrected: "최근 교정 완료"
    case .sourceSwitchFailed: "입력 소스 전환 실패"
    case .manuallyCorrected: "수동 변환 완료"
    case .undone: "마지막 교정 되돌림"
    case .repeatedInputPreserved: "반복 입력 유지"
    case .actionUnavailable: "현재 위치에서는 실행할 수 없음"
    }
  }
}

@MainActor
@Observable
final class AppModel {
  static let shared = AppModel()

  private(set) var permissions = PlatformCapabilities.currentPermissionSnapshot()
  private(set) var isCorrectionEnabled: Bool
  private(set) var automaticCorrectionThreshold: Int
  private(set) var isTerminalCorrectionEnabled: Bool
  private(set) var observationState: InputObservationState = .stopped
  private(set) var correctionActivity: CorrectionActivity = .idle
  private(set) var learningRules: [LearningRuleEntry] = []
  private(set) var excludedApplications: [String] = []
  private(set) var learningStoreRecovered = false
  private(set) var learningStorePermissionWarning = false
  private(set) var learningMessage = ""
  private(set) var manualShortcut: ShortcutPreset = .none
  private(set) var undoShortcut: ShortcutPreset = .none
  private(set) var shortcutMessage = "기본 전역 단축키는 등록하지 않습니다."
  private(set) var launchAtLoginStatus: LaunchAtLoginStatus = .notRegistered
  private(set) var launchAtLoginMessage = ""
  private(set) var isUpdatingLaunchAtLogin = false
  private(set) var inputMonitoringGuidance = ""
  private(set) var accessibilityGuidance = ""
  @ObservationIgnored private var observationRuntime: InputObservationRuntime?
  @ObservationIgnored private var inputSourceController: InputSourceController?
  @ObservationIgnored private var transactionCoordinator: CorrectionTransactionCoordinator?
  @ObservationIgnored private var terminalTransactionCoordinator: TerminalCorrectionCoordinator?
  @ObservationIgnored private var activeTransaction: Task<Void, Never>?
  @ObservationIgnored private var lastCorrectionRecord: CorrectionTransactionRecord?
  @ObservationIgnored private var pendingNeverRecord: CorrectionTransactionRecord?
  @ObservationIgnored private var manualCoordinator: ManualCorrectionCoordinator?
  @ObservationIgnored private var learningStore: LocalLearningStore?
  @ObservationIgnored private var shortcutManager: GlobalShortcutManager?
  @ObservationIgnored private var automaticCorrectionPreference: AutomaticCorrectionPreference?
  @ObservationIgnored private var automaticCorrectionThresholdPreference:
    AutomaticCorrectionThresholdPreference?
  @ObservationIgnored private var terminalCorrectionPreference: TerminalCorrectionPreference?
  @ObservationIgnored private var launchAtLoginController: LaunchAtLoginController?
  @ObservationIgnored private var externalApplicationTracker: ExternalApplicationTracker?
  @ObservationIgnored private var repeatedInputGuard = RepeatedInputGuard()
  @ObservationIgnored private var repeatedInputFocusIdentity: FocusedElementIdentity?
  @ObservationIgnored private var correctionDeletionTracker = CorrectionDeletionTracker()
  @ObservationIgnored private var deletionTrackingFocusIdentity: FocusedElementIdentity?
  @ObservationIgnored private var deletionTrackingSurface: InputSurface?
  @ObservationIgnored private var lastDeletionCaretLocation: Int?
  @ObservationIgnored private var deletionInspection: Task<Void, Never>?
  @ObservationIgnored private var deletionTextRewriter = FocusedTextRewriter()
  @ObservationIgnored private var neverRuleReviewNotifier: NeverRuleReviewNotifier?

  init() {
    let automaticCorrectionPreference = AutomaticCorrectionPreference()
    self.automaticCorrectionPreference = automaticCorrectionPreference
    isCorrectionEnabled = automaticCorrectionPreference.isEnabled
    let automaticCorrectionThresholdPreference = AutomaticCorrectionThresholdPreference()
    self.automaticCorrectionThresholdPreference = automaticCorrectionThresholdPreference
    automaticCorrectionThreshold = automaticCorrectionThresholdPreference.value
    let terminalCorrectionPreference = TerminalCorrectionPreference()
    self.terminalCorrectionPreference = terminalCorrectionPreference
    isTerminalCorrectionEnabled = terminalCorrectionPreference.isEnabled
    let inputSourceController = InputSourceController()
    self.inputSourceController = inputSourceController
    let learningStore = LocalLearningStore()
    self.learningStore = learningStore
    learningRules = learningStore.rules.entries
    excludedApplications = learningStore.excludedApplicationBundleIdentifiers
    learningStoreRecovered = learningStore.recoveredFromCorruption
    learningStorePermissionWarning = learningStore.permissionHardeningFailed
    transactionCoordinator = CorrectionTransactionCoordinator(
      inputSources: inputSourceController,
      isApplicationExcluded: { [weak learningStore] bundleIdentifier in
        learningStore?.isApplicationExcluded(bundleIdentifier) ?? true
      }
    )
    manualCoordinator = ManualCorrectionCoordinator(
      inputSources: inputSourceController,
      isApplicationExcluded: { [weak learningStore] bundleIdentifier in
        learningStore?.isApplicationExcluded(bundleIdentifier) ?? true
      }
    )
    let observationRuntime = InputObservationRuntime(
      isApplicationExcluded: { [weak learningStore] bundleIdentifier in
        learningStore?.isApplicationExcluded(bundleIdentifier) ?? true
      },
      allowsTerminalCorrection: { [weak terminalCorrectionPreference] in
        terminalCorrectionPreference?.isEnabled ?? false
      },
      handler: { [weak self] event in
        self?.handleRuntimeEvent(event)
      }
    )
    self.observationRuntime = observationRuntime
    terminalTransactionCoordinator = TerminalCorrectionCoordinator(
      inputSources: inputSourceController,
      currentSequence: { [weak observationRuntime] in
        observationRuntime?.eventSequence ?? UInt64.max
      },
      isApplicationExcluded: { [weak learningStore] bundleIdentifier in
        learningStore?.isApplicationExcluded(bundleIdentifier) ?? true
      }
    )
    shortcutManager = GlobalShortcutManager { [weak self] action in
      self?.handleShortcut(action)
    }
    let launchAtLoginController = LaunchAtLoginController()
    self.launchAtLoginController = launchAtLoginController
    launchAtLoginStatus = launchAtLoginController.status
    externalApplicationTracker = ExternalApplicationTracker(
      ownBundleIdentifier: Bundle.main.bundleIdentifier
    )
    let neverRuleReviewNotifier = NeverRuleReviewNotifier { [weak self] ruleID, decision in
      self?.reviewAutomaticallyExcludedRule(id: ruleID, decision: decision)
    }
    self.neverRuleReviewNotifier = neverRuleReviewNotifier
    neverRuleReviewNotifier.start()
    manualShortcut = Self.savedShortcut(forKey: "manualShortcut")
    undoShortcut = Self.savedShortcut(forKey: "undoShortcut")
    if !applyShortcutConfiguration(persist: false) {
      manualShortcut = .none
      undoShortcut = .none
      _ = applyShortcutConfiguration(persist: true)
      shortcutMessage = "등록할 수 없는 단축키를 안전하게 해제했습니다."
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

  var canUseManualCorrection: Bool {
    permissions.isAccessibilityTrusted && !permissions.isSecureInputEnabled
      && observationState != .protected
  }

  var canUndo: Bool {
    lastCorrectionRecord != nil && canUseManualCorrection
  }

  var canRememberLastUndoAsNever: Bool {
    pendingNeverRecord != nil
  }

  var neverConvertRules: [LearningRuleEntry] {
    learningRules.filter { $0.behavior == .never }
  }

  var alwaysConvertRules: [LearningRuleEntry] {
    learningRules.filter { $0.behavior == .always }
  }

  func refreshPermissions() {
    permissions = PlatformCapabilities.currentPermissionSnapshot()
    if permissions.canMonitorInput {
      inputMonitoringGuidance = ""
    }
    if permissions.isAccessibilityTrusted {
      accessibilityGuidance = ""
    }
    if isCorrectionEnabled, permissions.isReady,
      observationState == .stopped || observationState == .permissionRequired
    {
      _ = observationRuntime?.start()
    }
  }

  func setCorrectionEnabled(_ enabled: Bool) {
    guard enabled != isCorrectionEnabled else {
      return
    }
    if enabled {
      isCorrectionEnabled = true
      automaticCorrectionPreference?.setEnabled(true)
      refreshPermissions()
      guard observationRuntime?.start() == true else {
        return
      }
    } else {
      observationRuntime?.stop()
      activeTransaction?.cancel()
      activeTransaction = nil
      resetRepeatedInputGuard()
      isCorrectionEnabled = false
      automaticCorrectionPreference?.setEnabled(false)
      correctionActivity = .idle
    }
  }

  func setAutomaticCorrectionThreshold(_ value: Int) {
    let threshold = AutomaticCorrectionThreshold(value)
    guard threshold.value != automaticCorrectionThreshold else { return }
    automaticCorrectionThresholdPreference?.setValue(threshold.value)
    automaticCorrectionThreshold = threshold.value
  }

  func setTerminalCorrectionEnabled(_ enabled: Bool) {
    guard enabled != isTerminalCorrectionEnabled else { return }
    terminalCorrectionPreference?.setEnabled(enabled)
    isTerminalCorrectionEnabled = enabled
    resetRepeatedInputGuard()
    guard isCorrectionEnabled else { return }
    observationRuntime?.stop()
    _ = observationRuntime?.start()
  }

  func resumeSavedCorrectionIfPossible() {
    guard isCorrectionEnabled else { return }
    refreshPermissions()
  }

  func refreshLaunchAtLoginStatus() {
    launchAtLoginStatus = launchAtLoginController?.status ?? .repairRequired
  }

  func setLaunchAtLoginEnabled(_ enabled: Bool) {
    guard !isUpdatingLaunchAtLogin, let launchAtLoginController else { return }
    isUpdatingLaunchAtLogin = true
    launchAtLoginMessage = ""
    Task { @MainActor [weak self] in
      do {
        try await launchAtLoginController.setEnabled(enabled)
        self?.launchAtLoginStatus = launchAtLoginController.status
        if self?.launchAtLoginStatus == .requiresApproval {
          self?.launchAtLoginMessage = "macOS 로그인 항목 설정에서 한글변환을 허용하세요."
        } else if self?.launchAtLoginStatus == .repairRequired {
          self?.launchAtLoginMessage = "등록 상태를 복구하지 못했습니다. 다시 시도하거나 로그인 항목 설정을 확인하세요."
        }
      } catch {
        self?.launchAtLoginStatus = launchAtLoginController.status
        self?.launchAtLoginMessage =
          "로그인 실행 설정을 변경하지 못했습니다. 시스템 로그인 항목에서 차단 여부를 확인한 뒤 다시 시도하세요."
      }
      self?.isUpdatingLaunchAtLogin = false
    }
  }

  func openLoginItemsSettings() {
    launchAtLoginController?.openSystemSettings()
  }

  func requestInputMonitoring() {
    _ = PermissionController.requestInputMonitoring()
    refreshPermissions()
    guard !permissions.canMonitorInput else { return }
    inputMonitoringGuidance =
      "요청 창이 나타나지 않으면 목록의 +를 눌러 현재 한글변환 앱을 직접 추가하세요."
    openInputMonitoringSettings()
  }

  func requestAccessibility() {
    _ = PermissionController.requestAccessibility()
    refreshPermissions()
    guard !permissions.isAccessibilityTrusted else { return }
    accessibilityGuidance =
      "스위치가 켜져 있는데도 ‘필요함’이면 예전 한글변환 항목을 -로 제거한 뒤 현재 앱을 +로 다시 추가하세요."
    openAccessibilitySettings()
  }

  func openInputMonitoringSettings() {
    openSystemSettings(anchor: "Privacy_ListenEvent")
  }

  func openAccessibilitySettings() {
    openSystemSettings(anchor: "Privacy_Accessibility")
  }

  func revealCurrentApplication() {
    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
  }

  func relaunchApplication() {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(
      at: Bundle.main.bundleURL,
      configuration: configuration
    ) { [weak self] _, error in
      Task { @MainActor in
        guard error == nil else {
          self?.accessibilityGuidance = "앱을 다시 열지 못했습니다. 한글변환을 직접 종료한 뒤 다시 실행하세요."
          return
        }
        NSApp.terminate(nil)
      }
    }
  }

  func convertSelectionOrLastWord() {
    guard activeTransaction == nil, canUseManualCorrection, let manualCoordinator else {
      correctionActivity = .actionUnavailable
      return
    }
    correctionActivity = .checking
    activeTransaction = Task { @MainActor [weak self] in
      let result = await manualCoordinator.convertSelectionOrLastWord()
      guard let self else { return }
      switch result {
      case .corrected(let record):
        lastCorrectionRecord = record
        pendingNeverRecord = nil
        correctionActivity = .manuallyCorrected
        deliverCorrectionFeedback()
      case .cancelled(.sourceSwitchFailed(let record)):
        lastCorrectionRecord = record
        pendingNeverRecord = nil
        correctionActivity = .sourceSwitchFailed
      case .cancelled:
        correctionActivity = .actionUnavailable
      }
      activeTransaction = nil
    }
  }

  func undoLastCorrection() {
    guard activeTransaction == nil, canUndo, let manualCoordinator else {
      correctionActivity = .actionUnavailable
      return
    }
    let record = lastCorrectionRecord
    activeTransaction = Task { @MainActor [weak self] in
      let result = await manualCoordinator.undo(record)
      guard let self else { return }
      if result == .undone {
        pendingNeverRecord = record
        lastCorrectionRecord = nil
        correctionActivity = .undone
      } else {
        correctionActivity = .actionUnavailable
      }
      activeTransaction = nil
    }
  }

  func configureShortcut(_ action: ShortcutAction, preset: ShortcutPreset) {
    let oldManual = manualShortcut
    let oldUndo = undoShortcut
    switch action {
    case .manualConvert: manualShortcut = preset
    case .undo: undoShortcut = preset
    }
    guard applyShortcutConfiguration(persist: true) else {
      manualShortcut = oldManual
      undoShortcut = oldUndo
      _ = applyShortcutConfiguration(persist: false)
      return
    }
  }

  func addLearningRule(
    original: String,
    replacement: String,
    behavior: LearningRuleBehavior
  ) {
    do {
      guard
        try learningStore?.upsert(
          original: original,
          replacement: replacement,
          behavior: behavior
        ) != nil
      else {
        learningMessage = "서로 다른 1~64자 단어 쌍을 입력하세요."
        return
      }
      refreshLearningRules(message: "로컬 규칙을 저장했습니다.")
    } catch {
      learningMessage = "로컬 규칙을 저장하지 못했습니다."
    }
  }

  func removeLearningRule(id: UUID) {
    do {
      try learningStore?.remove(id: id)
      resetRepeatedInputGuard()
      refreshLearningRules(message: "로컬 규칙을 삭제했습니다.")
    } catch {
      learningMessage = "로컬 규칙을 삭제하지 못했습니다."
    }
  }

  func addNeverConvertToken(_ token: String) {
    let original = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let replacement = DubeolsikConverter.oppositeLayoutCandidate(for: original) else {
      learningMessage = "한글 또는 영문 한 단어를 입력하세요."
      return
    }
    addLearningRule(original: original, replacement: replacement, behavior: .never)
  }

  func addAlwaysConvertToken(_ token: String) {
    let original = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let replacement = DubeolsikConverter.oppositeLayoutCandidate(for: original) else {
      learningMessage = "한글 또는 영문 한 단어를 입력하세요."
      return
    }
    addLearningRule(original: original, replacement: replacement, behavior: .always)
  }

  func addExcludedApplication(_ bundleIdentifier: String) {
    guard bundleIdentifier != Bundle.main.bundleIdentifier else {
      learningMessage = "한글변환 자체는 제외할 수 없습니다."
      return
    }
    do {
      guard try learningStore?.addExcludedApplication(bundleIdentifier) == true else {
        learningMessage = "예: com.example.Editor 형식의 bundle ID를 입력하세요."
        return
      }
      refreshLearningRules(message: "앱 제외를 저장했습니다.")
    } catch {
      learningMessage = "앱 제외를 저장하지 못했습니다."
    }
  }

  func excludeRecentlyUsedApplication() {
    guard
      let bundleIdentifier = externalApplicationTracker?.lastExternalBundleIdentifier
    else {
      learningMessage = "제외할 앱으로 전환한 뒤 설정으로 돌아오세요."
      return
    }
    addExcludedApplication(bundleIdentifier)
  }

  func removeExcludedApplication(_ bundleIdentifier: String) {
    do {
      try learningStore?.removeExcludedApplication(bundleIdentifier)
      refreshLearningRules(message: "앱 제외를 삭제했습니다.")
    } catch {
      learningMessage = "앱 제외를 삭제하지 못했습니다."
    }
  }

  func rememberLastUndoAsNever() {
    guard let record = pendingNeverRecord else { return }
    let pair = rulePair(from: record)
    addLearningRule(original: pair.original, replacement: pair.replacement, behavior: .never)
    pendingNeverRecord = nil
  }

  func resetLearningRules() {
    do {
      try learningStore?.reset()
      pendingNeverRecord = nil
      refreshLearningRules(message: "모든 로컬 규칙을 초기화했습니다.")
    } catch {
      learningMessage = "로컬 규칙을 초기화하지 못했습니다."
    }
  }

  func exportLearningRules() {
    let panel = NSSavePanel()
    panel.title = "로컬 학습 규칙 내보내기"
    panel.nameFieldStringValue = "hankey-learning-rules.json"
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try learningStore?.export(to: url)
      learningMessage = "선택한 위치에 내보냈습니다."
    } catch {
      learningMessage = "로컬 규칙을 내보내지 못했습니다."
    }
  }

  func exportContentFreeDiagnosticReport() {
    let panel = NSSavePanel()
    panel.title = "콘텐츠 없는 진단 정보 내보내기"
    panel.nameFieldStringValue = "hankey-diagnostics.json"
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let version =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "development"
    let report = ContentFreeDiagnosticReport(
      appVersion: version,
      permissions: permissions,
      operationalState: operationalStatus.diagnosticCode,
      learningRuleCount: learningRules.count
    )
    do {
      try report.encoded().write(to: url, options: .atomic)
      learningMessage = "콘텐츠 없는 진단 정보를 내보냈습니다."
    } catch {
      learningMessage = "진단 정보를 내보내지 못했습니다."
    }
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
      if state != .observing {
        resetRepeatedInputGuard()
      }
      refreshPermissions()
    case .physicalInput(let activity, let focusIdentity, let surface):
      handlePhysicalInput(activity, focusIdentity: focusIdentity, surface: surface)
    case .wordCompleted(
      let word,
      let boundary,
      let focusIdentity,
      let surface,
      let eventSequence
    ):
      evaluateAndCorrect(
        word: word,
        boundary: boundary,
        focusIdentity: focusIdentity,
        surface: surface,
        eventSequence: eventSequence
      )
    }
  }

  private func evaluateAndCorrect(
    word: BufferedWord,
    boundary: WordBoundary,
    focusIdentity: FocusedElementIdentity,
    surface: InputSurface,
    eventSequence: UInt64
  ) {
    guard activeTransaction == nil else {
      return
    }
    if repeatedInputFocusIdentity != focusIdentity {
      repeatedInputGuard.reset()
      repeatedInputFocusIdentity = focusIdentity
    }
    guard
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
    if repeatedInputGuard.shouldSuppressCorrection(for: word) {
      rememberAutomaticallyExcludedPair(original: original, replacement: candidate)
      correctionActivity = .repeatedInputPreserved
      return
    }
    let evidence = SystemLexiconEvidenceProvider.evidence(
      original: original,
      candidate: candidate,
      activeLanguage: activeLanguage
    )
    let decision = CorrectionDecisionEngine(
      automaticMargin: AutomaticCorrectionThreshold(automaticCorrectionThreshold).automaticMargin
    ).decide(
      CorrectionRequest(
        token: original,
        activeLanguage: activeLanguage,
        surface: surface == .terminal ? .standardText : surface,
        explicitRule: learningStore?
          .behavior(original: original, replacement: candidate)?.explicitRule ?? .none,
        lexiconEvidence: evidence,
        leadingCommandPrefix: word.leadingCommandPrefix
      )
    )
    guard case .correct(let proposal) = decision else {
      return
    }

    if surface == .terminal {
      performTerminalCorrection(
        proposal: proposal,
        word: word,
        boundary: boundary,
        focusIdentity: focusIdentity,
        eventSequence: eventSequence
      )
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
        beginDeletionTracking(
          word: word,
          focusIdentity: focusIdentity,
          surface: surface,
          correctionStart: record.replacedRange.location,
          correctedCaretLocation: record.replacedRange.location
            + record.replacementWithBoundary.utf16.count
        )
        lastCorrectionRecord = record
        pendingNeverRecord = nil
        correctionActivity = .corrected
        deliverCorrectionFeedback()
      case .cancelled(.sourceSwitchFailed(let record)):
        beginDeletionTracking(
          word: word,
          focusIdentity: focusIdentity,
          surface: surface,
          correctionStart: record.replacedRange.location,
          correctedCaretLocation: record.replacedRange.location
            + record.replacementWithBoundary.utf16.count
        )
        lastCorrectionRecord = record
        pendingNeverRecord = nil
        correctionActivity = .sourceSwitchFailed
      case .cancelled:
        correctionActivity = .idle
      }
      activeTransaction = nil
    }
  }

  private func performTerminalCorrection(
    proposal: CorrectionProposal,
    word: BufferedWord,
    boundary: WordBoundary,
    focusIdentity: FocusedElementIdentity,
    eventSequence: UInt64
  ) {
    guard isTerminalCorrectionEnabled, let terminalTransactionCoordinator else { return }
    correctionActivity = .checking
    activeTransaction = Task { @MainActor [weak self] in
      let result = await terminalTransactionCoordinator.perform(
        proposal: proposal,
        boundary: boundary,
        expectedFocus: focusIdentity,
        expectedEventSequence: eventSequence
      )
      guard let self else { return }
      switch result {
      case .corrected(let record):
        beginTerminalDeletionTrackingIfSupported(
          record: record,
          word: word,
          focusIdentity: focusIdentity
        )
        lastCorrectionRecord = nil
        pendingNeverRecord = nil
        correctionActivity = .corrected
        deliverCorrectionFeedback()
      case .cancelled(.sourceSwitchFailed(let record)):
        beginTerminalDeletionTrackingIfSupported(
          record: record,
          word: word,
          focusIdentity: focusIdentity
        )
        lastCorrectionRecord = nil
        pendingNeverRecord = nil
        correctionActivity = .sourceSwitchFailed
      case .cancelled:
        correctionActivity = .idle
      }
      activeTransaction = nil
    }
  }

  private func beginTerminalDeletionTrackingIfSupported(
    record: TerminalCorrectionRecord,
    word: BufferedWord,
    focusIdentity: FocusedElementIdentity
  ) {
    guard record.supportsDeletionTracking else {
      clearDeletionTracking()
      return
    }
    beginDeletionTracking(
      word: word,
      focusIdentity: focusIdentity,
      surface: .terminal,
      correctionStart: record.correctionStart,
      correctedCaretLocation: record.correctedCaretLocation
    )
  }

  private func beginDeletionTracking(
    word: BufferedWord,
    focusIdentity: FocusedElementIdentity,
    surface: InputSurface,
    correctionStart: Int,
    correctedCaretLocation: Int
  ) {
    deletionInspection?.cancel()
    deletionInspection = nil
    correctionDeletionTracker.beginTracking(
      word: word,
      correctionStart: correctionStart,
      correctedCaretLocation: correctedCaretLocation
    )
    deletionTrackingFocusIdentity = focusIdentity
    deletionTrackingSurface = surface
    lastDeletionCaretLocation = correctedCaretLocation
    repeatedInputGuard.cancelPendingComparison()
    repeatedInputFocusIdentity = focusIdentity
  }

  private func handlePhysicalInput(
    _ activity: PhysicalInputActivity,
    focusIdentity: FocusedElementIdentity,
    surface: InputSurface
  ) {
    switch activity {
    case .deletion:
      guard correctionDeletionTracker.isTracking else {
        repeatedInputGuard.cancelPendingComparison()
        return
      }
      guard
        deletionTrackingFocusIdentity == focusIdentity,
        deletionTrackingSurface == surface,
        let previousCaret = lastDeletionCaretLocation
      else {
        resetRepeatedInputGuard()
        return
      }
      inspectCaretAfterDeletion(
        expectedFocus: focusIdentity,
        surface: surface,
        previousCaret: previousCaret
      )

    case .nonDeletionInput:
      if correctionDeletionTracker.isTracking {
        clearDeletionTracking()
      }

    case .invalidated(let reason):
      guard reason != .inputSourceChanged else { return }
      if correctionDeletionTracker.isTracking {
        clearDeletionTracking()
      }
      repeatedInputGuard.cancelPendingComparison()
    }
  }

  private func inspectCaretAfterDeletion(
    expectedFocus: FocusedElementIdentity,
    surface: InputSurface,
    previousCaret: Int
  ) {
    deletionInspection?.cancel()
    deletionInspection = Task { @MainActor [weak self] in
      guard let self else { return }
      for _ in 0..<4 {
        try? await Task.sleep(for: .milliseconds(8))
        guard !Task.isCancelled else { return }
        guard
          let snapshot = currentCaretSnapshot(surface: surface),
          snapshot.identity == expectedFocus,
          snapshot.selection.length == 0
        else {
          resetRepeatedInputGuard()
          return
        }
        let location = snapshot.selection.location
        guard location != previousCaret else { continue }
        lastDeletionCaretLocation = location
        switch correctionDeletionTracker.observeCaret(location: location) {
        case .correctionFullyDeleted(let word):
          repeatedInputGuard.armSuppressionAfterDeletion(for: word)
          repeatedInputFocusIdentity = expectedFocus
          clearDeletionTracking()
        case .cancelled:
          clearDeletionTracking()
        case .none:
          deletionInspection = nil
        }
        return
      }
      clearDeletionTracking()
    }
  }

  private func currentCaretSnapshot(surface: InputSurface) -> FocusedTextSnapshot? {
    surface == .terminal
      ? TerminalCaretInspector.currentSnapshot()
      : deletionTextRewriter.currentSnapshot()
  }

  private func clearDeletionTracking() {
    deletionInspection?.cancel()
    deletionInspection = nil
    correctionDeletionTracker.reset()
    deletionTrackingFocusIdentity = nil
    deletionTrackingSurface = nil
    lastDeletionCaretLocation = nil
  }

  private func rememberAutomaticallyExcludedPair(original: String, replacement: String) {
    do {
      guard
        let entry = try learningStore?.upsert(
          original: original,
          replacement: replacement,
          behavior: .never
        )
      else { return }
      refreshLearningRules(message: "삭제 후 다시 입력한 단어를 변환 제외에 추가했습니다.")
      neverRuleReviewNotifier?.notify(ruleID: entry.id)
    } catch {
      learningMessage = "변환 제외 규칙을 저장하지 못했습니다."
    }
  }

  private func reviewAutomaticallyExcludedRule(
    id: UUID,
    decision: NeverRuleReviewDecision
  ) {
    guard let rule = learningStore?.rules.entries.first(where: { $0.id == id }) else { return }
    switch decision {
    case .keepExcluded:
      learningMessage = "변환 제외 규칙을 유지합니다."
    case .alwaysConvert:
      do {
        guard
          try learningStore?.upsert(
            original: rule.original,
            replacement: rule.replacement,
            behavior: .always
          ) != nil
        else { return }
        resetRepeatedInputGuard()
        refreshLearningRules(message: "해당 단어를 항상 변환 규칙으로 옮겼습니다.")
      } catch {
        learningMessage = "항상 변환 규칙으로 옮기지 못했습니다."
      }
    }
  }

  private func handleShortcut(_ action: ShortcutAction) {
    switch action {
    case .manualConvert: convertSelectionOrLastWord()
    case .undo: undoLastCorrection()
    }
  }

  private func resetRepeatedInputGuard() {
    clearDeletionTracking()
    repeatedInputGuard.reset()
    repeatedInputFocusIdentity = nil
  }

  private func deliverCorrectionFeedback() {
    if UserDefaults.standard.object(forKey: "showCorrectionFeedback") == nil
      || UserDefaults.standard.bool(forKey: "showCorrectionFeedback")
    {
      NSAccessibility.post(
        element: NSApplication.shared,
        notification: .announcementRequested,
        userInfo: [.announcement: "한영 입력 교정을 완료했습니다."]
      )
    }
    if UserDefaults.standard.bool(forKey: "playCorrectionSound") {
      NSSound(named: NSSound.Name("Tink"))?.play()
    }
  }

  @discardableResult
  private func applyShortcutConfiguration(persist: Bool) -> Bool {
    let configuration = ShortcutConfiguration(
      manualConvert: manualShortcut,
      undo: undoShortcut
    )
    guard let results = shortcutManager?.apply(configuration) else {
      shortcutMessage = "전역 단축키 서비스를 사용할 수 없습니다."
      return false
    }
    let failed = results.values.contains { $0 == .conflict || $0 == .unavailable }
    guard !failed else {
      shortcutMessage =
        configuration.hasInternalCollision
        ? "두 동작에 같은 단축키를 지정할 수 없습니다."
        : "이미 다른 앱이 사용 중인 단축키입니다."
      return false
    }
    if persist {
      UserDefaults.standard.set(manualShortcut.rawValue, forKey: "manualShortcut")
      UserDefaults.standard.set(undoShortcut.rawValue, forKey: "undoShortcut")
    }
    shortcutMessage = "지정한 단축키는 이 Mac에서만 사용됩니다."
    return true
  }

  private static func savedShortcut(forKey key: String) -> ShortcutPreset {
    guard
      let value = UserDefaults.standard.string(forKey: key),
      let preset = ShortcutPreset(rawValue: value)
    else {
      return .none
    }
    return preset
  }

  private func refreshLearningRules(message: String) {
    learningRules = learningStore?.rules.entries ?? []
    excludedApplications = learningStore?.excludedApplicationBundleIdentifiers ?? []
    learningMessage = message
  }

  private func rulePair(
    from record: CorrectionTransactionRecord
  ) -> (original: String, replacement: String) {
    var original = record.originalWithBoundary
    var replacement = record.replacementWithBoundary
    if let originalLast = original.last, originalLast == replacement.last,
      originalLast.isWhitespace || originalLast.isPunctuation
    {
      original.removeLast()
      replacement.removeLast()
    }
    return (original, replacement)
  }
}
