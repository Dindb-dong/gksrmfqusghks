import AppKit
import HanKeyCore
import HanKeyPlatformMac
import SwiftUI

@main
struct HanKeyApplication: App {
  @State private var model = AppModel()

  var body: some Scene {
    MenuBarExtra(HanKeyCoreMetadata.displayName, systemImage: model.menuBarSymbol) {
      MenuBarContent(model: model)
    }

    Settings {
      SettingsView(model: model)
    }
  }
}

@MainActor
@Observable
final class AppModel {
  private(set) var permissions = PlatformCapabilities.currentPermissionSnapshot()
  private(set) var isCorrectionEnabled = false
  private(set) var observationState: InputObservationState = .stopped
  private(set) var correctionStatus = "대기 중"
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

  var menuBarSymbol: String {
    if permissions.isSecureInputEnabled {
      return "lock.shield"
    }
    if !permissions.isReady {
      return "exclamationmark.shield"
    }
    return isCorrectionEnabled ? "character.cursor.ibeam" : "pause.circle"
  }

  var statusTitle: String {
    if permissions.isSecureInputEnabled || observationState == .protected {
      return "보안 입력 보호 중"
    }
    if !permissions.canMonitorInput || !permissions.isAccessibilityTrusted {
      return "권한 설정 필요"
    }
    return isCorrectionEnabled ? "자동 교정 켜짐" : "자동 교정 일시정지"
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

    correctionStatus = "교정 확인 중"
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
        correctionStatus = "최근 교정 완료"
      case .cancelled(.sourceSwitchFailed(let record)):
        lastCorrectionRecord = record
        correctionStatus = "입력 소스 전환 실패"
      case .cancelled:
        correctionStatus = "대기 중"
      }
      activeTransaction = nil
    }
  }
}

private struct MenuBarContent: View {
  @Bindable var model: AppModel
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    Text(model.statusTitle)

    Toggle(
      "자동 교정",
      isOn: Binding(
        get: { model.isCorrectionEnabled },
        set: { model.setCorrectionEnabled($0) }
      )
    )
    .disabled(!model.isCorrectionEnabled && !model.permissions.isReady)

    Divider()

    Button("권한 상태 새로고침") {
      model.refreshPermissions()
    }

    Button("설정…") {
      openSettings()
    }
    .keyboardShortcut(",", modifiers: .command)

    Divider()

    Button("한글변환 종료") {
      NSApplication.shared.terminate(nil)
    }
    .keyboardShortcut("q", modifiers: .command)
  }
}

private struct SettingsView: View {
  @Bindable var model: AppModel

  var body: some View {
    Form {
      Section("상태") {
        LabeledContent("입력 모니터링") {
          PermissionLabel(isGranted: model.permissions.canMonitorInput)
        }
        LabeledContent("손쉬운 사용") {
          PermissionLabel(isGranted: model.permissions.isAccessibilityTrusted)
        }
        LabeledContent("보안 입력") {
          Text(model.permissions.isSecureInputEnabled ? "보호 중" : "비활성")
        }
      }

      Section("자동 교정") {
        Toggle(
          "자동 교정 사용",
          isOn: Binding(
            get: { model.isCorrectionEnabled },
            set: { model.setCorrectionEnabled($0) }
          )
        )
        .disabled(!model.isCorrectionEnabled && !model.permissions.isReady)
        LabeledContent("최근 동작", value: model.correctionStatus)
        Text("고신뢰 단어만 클립보드 없이 교체하고, 성공한 뒤 다음 입력 소스를 맞춥니다.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      Section("권한") {
        Button("입력 모니터링 요청") {
          model.requestInputMonitoring()
        }
        Button("손쉬운 사용 요청") {
          model.requestAccessibility()
        }
      }

      Section("개인정보") {
        Text("한글변환은 입력 내용을 네트워크로 전송하거나 디스크에 기록하지 않습니다.")
      }

      Button("권한 상태 새로고침") {
        model.refreshPermissions()
      }
    }
    .formStyle(.grouped)
    .frame(width: 560, height: 420)
    .padding()
  }
}

private struct PermissionLabel: View {
  let isGranted: Bool

  var body: some View {
    Label(
      isGranted ? "허용됨" : "필요함",
      systemImage: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle"
    )
    .foregroundStyle(isGranted ? .green : .orange)
  }
}
