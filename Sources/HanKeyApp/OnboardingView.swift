import AppKit
import HanKeyCore
import SwiftUI

private enum OnboardingStep: Int, CaseIterable {
  case privacy
  case permissions
  case demo
  case ready

  var title: String {
    switch self {
    case .privacy: "먼저, 입력을 어떻게 다루는지"
    case .permissions: "두 권한이 필요한 이유"
    case .demo: "이 Mac 안에서 시험해 보기"
    case .ready: "준비가 끝났습니다"
    }
  }
}

struct OnboardingView: View {
  @Bindable var model: AppModel
  let onFinish: () -> Void
  @AppStorage("onboardingCompleted") private var onboardingCompleted = false
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var step: OnboardingStep = .privacy
  @State private var demoInput = "gksrmffh"
  @State private var demoOutput = ""

  init(model: AppModel, onFinish: @escaping () -> Void) {
    self.model = model
    self.onFinish = onFinish
    #if DEBUG
      let prefix = "--onboarding-step="
      let requestedStep = ProcessInfo.processInfo.arguments
        .first(where: { $0.hasPrefix(prefix) })
        .flatMap { Int($0.dropFirst(prefix.count)) }
        .flatMap(OnboardingStep.init(rawValue:))
      _step = State(initialValue: requestedStep ?? .privacy)
    #endif
  }

  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 20) {
        HStack {
          Label("한글변환", systemImage: "character.cursor.ibeam")
            .font(.headline)
          Spacer()
          Text("\(step.rawValue + 1) / \(OnboardingStep.allCases.count)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }

        Text(step.title)
          .font(.largeTitle.weight(.semibold))
          .accessibilityAddTraits(.isHeader)

        Group {
          switch step {
          case .privacy:
            privacyStep
          case .permissions:
            permissionsStep
          case .demo:
            demoStep
          case .ready:
            readyStep
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
      }
      .padding(28)

      Divider()

      HStack {
        HStack(spacing: 6) {
          ForEach(OnboardingStep.allCases, id: \.rawValue) { item in
            Circle()
              .fill(
                item.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.25)
              )
              .frame(width: 7, height: 7)
              .accessibilityHidden(true)
          }
        }

        Spacer()

        if step != .privacy {
          Button("이전") {
            move(to: OnboardingStep(rawValue: step.rawValue - 1) ?? .privacy)
          }
        }

        if step == .ready {
          Button(model.permissions.isReady ? "자동 교정 켜고 시작" : "일시정지로 시작") {
            finish(enableCorrection: model.permissions.isReady)
          }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
        } else {
          Button("계속") {
            move(to: OnboardingStep(rawValue: step.rawValue + 1) ?? .ready)
          }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
        }
      }
      .padding(16)
    }
    .frame(width: 640, height: 520)
    .task {
      if onboardingCompleted {
        onFinish()
        dismiss()
      } else {
        NSApp.activate(ignoringOtherApps: true)
        model.refreshPermissions()
      }
    }
    .accessibilityIdentifier("onboarding-window")
  }

  private var privacyStep: some View {
    VStack(alignment: .leading, spacing: 20) {
      LocalOnlyDisclosure()

      Divider()

      VStack(alignment: .leading, spacing: 10) {
        Label("현재 단어에 필요한 키 위치만 잠시 보관", systemImage: "memorychip")
        Label("앱 전환·클릭·10초 유휴 시 즉시 폐기", systemImage: "trash")
        Label("URL·주소·코드·랜덤값은 자동 교정 제외", systemImage: "nosign")
      }
      .font(.subheadline)
    }
  }

  private var permissionsStep: some View {
    VStack(alignment: .leading, spacing: 18) {
      PermissionRow(
        title: "입력 모니터링",
        explanation: "어느 입력 소스에서 어떤 물리 키 위치가 눌렸는지 판별합니다. 문장 전체를 읽지 않습니다.",
        isGranted: model.permissions.canMonitorInput,
        request: model.requestInputMonitoring,
        openSettings: model.openInputMonitoringSettings
      )

      Divider()

      PermissionRow(
        title: "손쉬운 사용",
        explanation: "교정 직전 같은 필드와 커서인지 확인하고, 검증된 단어 범위만 바꿉니다.",
        isGranted: model.permissions.isAccessibilityTrusted,
        request: model.requestAccessibility,
        openSettings: model.openAccessibilitySettings
      )

      HStack {
        Button("권한 상태 새로고침") {
          model.refreshPermissions()
        }
        Spacer()
        Text(model.permissions.hasRequiredPermissions ? "두 권한이 준비됐습니다." : "나중에 설정해도 됩니다.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var demoStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("이 입력란은 온보딩 창 안에서만 변환합니다. 전역 키 관찰 권한 없이도 핵심 변환을 확인할 수 있습니다.")
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      TextField("영타 또는 한글 자모 입력", text: $demoInput)
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("onboarding-demo-input")

      HStack {
        Button("반대 레이아웃으로 변환") {
          demoOutput = convertedDemo(demoInput)
        }
        .disabled(demoInput.isEmpty)
        .keyboardShortcut(.return, modifiers: [.command])

        Button("예시 복원") {
          demoInput = "gksrmffh"
          demoOutput = ""
        }
      }

      if !demoOutput.isEmpty {
        LabeledContent("변환 결과") {
          Text(demoOutput)
            .font(.title3.monospaced())
            .textSelection(.enabled)
        }
        .padding(.top, 4)
        .accessibilityIdentifier("onboarding-demo-result")
      }

      Text("예: gksrmffh → 한글로 · ㅛㅐㅜㄴ댜 → yonsei")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private var readyStep: some View {
    VStack(alignment: .leading, spacing: 20) {
      StatusHeader(status: model.operationalStatus)

      if model.permissions.hasRequiredPermissions {
        Label("자동 교정을 켜기 전까지는 키 입력을 관찰하지 않습니다.", systemImage: "checkmark.circle")
      } else {
        Label("권한이 없어 자동 교정은 일시정지 상태로 시작합니다.", systemImage: "pause.circle")
        Text("메뉴 막대의 ‘설정…’에서 언제든 권한 이유를 다시 확인하고 허용할 수 있습니다.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Text("정상 상태에서는 메뉴 막대에서 조용히 동작하며, 보안 입력과 지원하지 않는 편집기에서는 자동으로 멈춥니다.")
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func convertedDemo(_ value: String) -> String {
    if value.unicodeScalars.contains(where: { scalar in
      (0xAC00...0xD7A3).contains(scalar.value)
        || (0x1100...0x11FF).contains(scalar.value)
        || (0x3130...0x318F).contains(scalar.value)
    }) {
      return DubeolsikConverter.decomposeToQWERTY(value)
    }
    return DubeolsikConverter.compose(value)
  }

  private func move(to nextStep: OnboardingStep) {
    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
      step = nextStep
    }
    model.refreshPermissions()
  }

  private func finish(enableCorrection: Bool) {
    if enableCorrection {
      model.setCorrectionEnabled(true)
    }
    onboardingCompleted = true
    onFinish()
    dismiss()
  }
}
