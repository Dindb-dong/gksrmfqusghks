import HanKeyCore
import HanKeyPlatformMac
import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
  case general = "일반"
  case safety = "안전"
  case shortcuts = "단축키"
  case learning = "학습"
  case about = "정보"

  var id: Self { self }
}

struct SettingsView: View {
  @Bindable var model: AppModel
  @State private var section: SettingsSection = .general
  @AppStorage("showCorrectionFeedback") private var showCorrectionFeedback = true
  @AppStorage("playCorrectionSound") private var playCorrectionSound = false
  @State private var ruleOriginal = ""
  @State private var ruleReplacement = ""
  @State private var ruleBehavior: LearningRuleBehavior = .never
  @State private var confirmsLearningReset = false
  @State private var showsApplicationPicker = false

  var body: some View {
    VStack(spacing: 0) {
      Picker("설정 영역", selection: $section) {
        ForEach(SettingsSection.allCases) { section in
          Text(section.rawValue).tag(section)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .padding(16)
      .accessibilityIdentifier("settings-section-picker")

      Divider()

      Form {
        switch section {
        case .general:
          generalSettings
        case .safety:
          safetySettings
        case .shortcuts:
          shortcutSettings
        case .learning:
          learningSettings
        case .about:
          aboutSettings
        }
      }
      .formStyle(.grouped)
      .scrollContentBackground(.hidden)
    }
    .frame(minWidth: 560, idealWidth: 620, maxWidth: 760, minHeight: 440, idealHeight: 500)
    .task {
      model.refreshLaunchAtLoginStatus()
    }
    .sheet(isPresented: $showsApplicationPicker) {
      InstalledApplicationPicker(
        excludedBundleIdentifiers: Set(model.excludedApplications),
        ownBundleIdentifier: Bundle.main.bundleIdentifier
      ) { application in
        model.addExcludedApplication(application.bundleIdentifier)
      }
    }
  }

  @ViewBuilder
  private var generalSettings: some View {
    Section("현재 상태") {
      StatusHeader(status: model.operationalStatus)

      Toggle(
        "자동 교정 사용",
        isOn: Binding(
          get: { model.isCorrectionEnabled },
          set: { model.setCorrectionEnabled($0) }
        )
      )
      .disabled(!model.isCorrectionEnabled && !model.permissions.isReady)

      LabeledContent("최근 동작", value: model.correctionActivity.title)
    }

    Section("시작과 피드백") {
      Toggle("교정 알림", isOn: $showCorrectionFeedback)
        .accessibilityHint("VoiceOver로 교정 완료를 알립니다.")
      Toggle("교정 효과음", isOn: $playCorrectionSound)

      Toggle(
        "로그인 시 한글변환 실행",
        isOn: Binding(
          get: { model.launchAtLoginStatus.isEnabled },
          set: { model.setLaunchAtLoginEnabled($0) }
        )
      )
      .disabled(model.isUpdatingLaunchAtLogin)
      LabeledContent("로그인 실행 상태", value: model.launchAtLoginStatus.title)
      if model.launchAtLoginStatus == .requiresApproval
        || model.launchAtLoginStatus == .repairRequired
      {
        Button("로그인 항목 설정 열기") {
          model.openLoginItemsSettings()
        }
      }
      if !model.launchAtLoginMessage.isEmpty {
        Text(model.launchAtLoginMessage)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }

    Section("권한") {
      PermissionRow(
        title: "입력 모니터링",
        explanation: "물리 키 위치를 읽어 현재 단어만 메모리에서 판별합니다.",
        isGranted: model.permissions.canMonitorInput,
        guidance: model.inputMonitoringGuidance,
        request: model.requestInputMonitoring,
        openSettings: model.openInputMonitoringSettings,
        revealApplication: model.revealCurrentApplication,
        relaunchApplication: model.relaunchApplication
      )
      PermissionRow(
        title: "손쉬운 사용",
        explanation: "교정 직전 포커스와 범위를 확인하고 해당 단어만 바꿉니다.",
        isGranted: model.permissions.isAccessibilityTrusted,
        guidance: model.accessibilityGuidance,
        request: model.requestAccessibility,
        openSettings: model.openAccessibilitySettings,
        revealApplication: model.revealCurrentApplication,
        relaunchApplication: model.relaunchApplication
      )

      Button("권한 상태 새로고침") {
        model.refreshPermissions()
      }
    }
  }

  @ViewBuilder
  private var safetySettings: some View {
    Section("로컬 처리") {
      LocalOnlyDisclosure()
    }

    Section("자동으로 보호되는 곳") {
      Label("비밀번호·보안 입력", systemImage: "lock.shield")
      Label("브라우저 주소창", systemImage: "link")
      Label("IDE·원격 데스크톱", systemImage: "desktopcomputer")
      Text("지원 여부를 확신할 수 없으면 교정하지 않습니다. 클립보드 fallback도 사용하지 않습니다.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    Section("터미널") {
      Toggle(
        "터미널에서 자연어 자동 교정",
        isOn: Binding(
          get: { model.isTerminalCorrectionEnabled },
          set: { model.setTerminalCorrectionEnabled($0) }
        )
      )
      Text(
        "cmux·Terminal·iTerm2 등에서 Space로 끝난 고신뢰 단어만 교정합니다. Enter, Tab, 문장부호, 경로·주소·옵션은 바꾸지 않습니다."
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
      Label(
        "터미널은 선택 문자열 검증이 불가능해 이 기능은 기본으로 꺼져 있습니다. 비밀번호 입력 전에는 터미널의 Secure Keyboard Entry도 켜세요.",
        systemImage: "exclamationmark.shield"
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
    }

    Section("사용자 앱 제외") {
      HStack {
        Button("설치된 앱 선택…") {
          showsApplicationPicker = true
        }
        Button("최근 사용 앱 제외") {
          model.excludeRecentlyUsedApplication()
        }
      }
      Text("제외할 앱으로 한 번 전환한 뒤 설정으로 돌아오면 최근 앱을 바로 추가할 수 있습니다.")
        .font(.footnote)
        .foregroundStyle(.secondary)

      if model.excludedApplications.isEmpty {
        Text("추가로 제외한 앱이 없습니다.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(model.excludedApplications, id: \.self) { bundleIdentifier in
          HStack {
            ExcludedApplicationLabel(bundleIdentifier: bundleIdentifier)
            Spacer()
            Button(role: .destructive) {
              model.removeExcludedApplication(bundleIdentifier)
            } label: {
              Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("제외 앱 삭제")
          }
        }
      }
      Text("내장 보호 앱과 보안 필드는 이 목록에서 해제할 수 없습니다.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var shortcutSettings: some View {
    Section("전역 단축키") {
      Picker(
        "선택 영역 또는 마지막 단어 변환",
        selection: Binding(
          get: { model.manualShortcut },
          set: { model.configureShortcut(.manualConvert, preset: $0) }
        )
      ) {
        ForEach(ShortcutPreset.allCases, id: \.self) { preset in
          Text(preset.title).tag(preset)
        }
      }

      Picker(
        "마지막 교정 되돌리기",
        selection: Binding(
          get: { model.undoShortcut },
          set: { model.configureShortcut(.undo, preset: $0) }
        )
      ) {
        ForEach(ShortcutPreset.allCases, id: \.self) { preset in
          Text(preset.title).tag(preset)
        }
      }

      Text(model.shortcutMessage)
        .font(.footnote)
        .foregroundStyle(.secondary)
      Text("충돌을 피하기 위해 기본 전역 단축키를 강제로 등록하지 않습니다.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var learningSettings: some View {
    if model.learningStoreRecovered {
      Section {
        Label(
          "손상된 규칙 파일을 격리하고 빈 규칙으로 복구했습니다.",
          systemImage: "exclamationmark.triangle"
        )
      }
    }

    if model.learningStorePermissionWarning {
      Section {
        Label(
          "규칙 파일 권한을 강화하지 못했습니다. 새 규칙 저장을 중단하고 파일 권한을 확인하세요.",
          systemImage: "lock.trianglebadge.exclamationmark"
        )
      }
    }

    Section("로컬 규칙 추가") {
      TextField("입력된 단어", text: $ruleOriginal)
      TextField("변환 후보", text: $ruleReplacement)
      Picker("동작", selection: $ruleBehavior) {
        Text("항상 변환").tag(LearningRuleBehavior.always)
        Text("변환하지 않음").tag(LearningRuleBehavior.never)
      }
      .pickerStyle(.segmented)

      Button("규칙 저장") {
        model.addLearningRule(
          original: ruleOriginal,
          replacement: ruleReplacement,
          behavior: ruleBehavior
        )
        if model.learningMessage == "로컬 규칙을 저장했습니다." {
          ruleOriginal = ""
          ruleReplacement = ""
        }
      }
      .disabled(ruleOriginal.isEmpty || ruleReplacement.isEmpty)

      if model.canRememberLastUndoAsNever {
        Button("방금 되돌린 교정을 ‘변환하지 않음’으로 저장") {
          model.rememberLastUndoAsNever()
        }
      }
    }

    Section("저장된 규칙") {
      if model.learningRules.isEmpty {
        ContentUnavailableView(
          "저장된 규칙 없음",
          systemImage: "checkmark.shield",
          description: Text("명시적으로 추가한 단어 쌍만 이 Mac에 저장됩니다.")
        )
      } else {
        ForEach(model.learningRules) { rule in
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text("\(rule.original) → \(rule.replacement)")
                .textSelection(.enabled)
              Text(rule.behavior == .always ? "항상 변환" : "변환하지 않음")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
              model.removeLearningRule(id: rule.id)
            } label: {
              Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(rule.original) 규칙 삭제")
          }
        }
      }
    }

    Section("데이터 관리") {
      HStack {
        Button("JSON으로 내보내기…") {
          model.exportLearningRules()
        }
        Button("모든 로컬 데이터 초기화", role: .destructive) {
          confirmsLearningReset = true
        }
        .disabled(model.learningRules.isEmpty && model.excludedApplications.isEmpty)
      }
      if !model.learningMessage.isEmpty {
        Text(model.learningMessage)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      Text("내보내기는 사용자가 선택한 위치에만 쓰며 자동 동기화하지 않습니다.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .confirmationDialog(
      "모든 로컬 데이터를 초기화할까요?",
      isPresented: $confirmsLearningReset,
      titleVisibility: .visible
    ) {
      Button("모든 로컬 데이터 초기화", role: .destructive) {
        model.resetLearningRules()
      }
      Button("취소", role: .cancel) {}
    } message: {
      Text("단어 규칙과 사용자 앱 제외를 삭제합니다. 자동 교정과 권한 설정은 유지됩니다.")
    }
  }

  @ViewBuilder
  private var aboutSettings: some View {
    Section {
      VStack(alignment: .leading, spacing: 8) {
        Text(HanKeyCoreMetadata.displayName)
          .font(.title2.weight(.semibold))
        Text("로컬 전용 한↔영 입력 복구 도구")
          .foregroundStyle(.secondary)
        Text("일반 맞춤법 교정, 번역, 클라우드 동기화 기능은 포함하지 않습니다.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }

    Section("프로젝트") {
      Link(
        "GitHub에서 소스 보기", destination: URL(string: "https://github.com/Dindb-dong/gksrmfqusghks")!)
      Text("라이선스와 보안 정책은 공개 저장소에서 확인할 수 있습니다.")
        .font(.footnote)
        .foregroundStyle(.secondary)
      Button("콘텐츠 없는 진단 정보 내보내기…") {
        model.exportContentFreeDiagnosticReport()
      }
      Text("앱·OS 버전, 아키텍처, 권한과 상태 코드, 규칙 개수만 포함합니다. 입력 내용과 앱 이름은 포함하지 않습니다.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }
}
