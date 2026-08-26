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
}

enum CorrectionActivity: Equatable {
  case idle
  case checking
  case corrected
  case sourceSwitchFailed
  case manuallyCorrected
  case undone
  case actionUnavailable

  var title: String {
    switch self {
    case .idle: "대기 중"
    case .checking: "교정 확인 중"
    case .corrected: "최근 교정 완료"
    case .sourceSwitchFailed: "입력 소스 전환 실패"
    case .manuallyCorrected: "수동 변환 완료"
    case .undone: "마지막 교정 되돌림"
    case .actionUnavailable: "현재 위치에서는 실행할 수 없음"
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
  private(set) var learningRules: [LearningRuleEntry] = []
  private(set) var learningStoreRecovered = false
  private(set) var learningMessage = ""
  private(set) var manualShortcut: ShortcutPreset = .none
  private(set) var undoShortcut: ShortcutPreset = .none
  private(set) var shortcutMessage = "기본 전역 단축키는 등록하지 않습니다."
  @ObservationIgnored private var observationRuntime: InputObservationRuntime?
  @ObservationIgnored private var inputSourceController: InputSourceController?
  @ObservationIgnored private var transactionCoordinator: CorrectionTransactionCoordinator?
  @ObservationIgnored private var activeTransaction: Task<Void, Never>?
  @ObservationIgnored private var lastCorrectionRecord: CorrectionTransactionRecord?
  @ObservationIgnored private var pendingNeverRecord: CorrectionTransactionRecord?
  @ObservationIgnored private var manualCoordinator: ManualCorrectionCoordinator?
  @ObservationIgnored private var learningStore: LocalLearningStore?
  @ObservationIgnored private var shortcutManager: GlobalShortcutManager?

  init() {
    let inputSourceController = InputSourceController()
    self.inputSourceController = inputSourceController
    transactionCoordinator = CorrectionTransactionCoordinator(inputSources: inputSourceController)
    manualCoordinator = ManualCorrectionCoordinator(inputSources: inputSourceController)
    let learningStore = LocalLearningStore()
    self.learningStore = learningStore
    learningRules = learningStore.rules.entries
    learningStoreRecovered = learningStore.recoveredFromCorruption
    observationRuntime = InputObservationRuntime { [weak self] event in
      self?.handleRuntimeEvent(event)
    }
    shortcutManager = GlobalShortcutManager { [weak self] action in
      self?.handleShortcut(action)
    }
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
      case .corrected(let record), .cancelled(.sourceSwitchFailed(let record)):
        lastCorrectionRecord = record
        pendingNeverRecord = nil
        correctionActivity = result.isFullyCorrected ? .manuallyCorrected : .sourceSwitchFailed
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
      refreshLearningRules(message: "로컬 규칙을 삭제했습니다.")
    } catch {
      learningMessage = "로컬 규칙을 삭제하지 못했습니다."
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
        explicitRule: learningStore?
          .behavior(original: original, replacement: candidate)?.explicitRule ?? .none,
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
        pendingNeverRecord = nil
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
        pendingNeverRecord = nil
        correctionActivity = .sourceSwitchFailed
      case .cancelled:
        correctionActivity = .idle
      }
      activeTransaction = nil
    }
  }

  private func handleShortcut(_ action: ShortcutAction) {
    switch action {
    case .manualConvert: convertSelectionOrLastWord()
    case .undo: undoLastCorrection()
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

extension ManualCorrectionResult {
  fileprivate var isFullyCorrected: Bool {
    if case .corrected = self { return true }
    return false
  }
}
