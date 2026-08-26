import HanKeyCore
import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
  case general = "일반"
  case safety = "안전"
  case shortcuts = "단축키"
  case about = "정보"

  var id: Self { self }
}

struct SettingsView: View {
  @Bindable var model: AppModel
  @State private var section: SettingsSection = .general
  @AppStorage("showCorrectionFeedback") private var showCorrectionFeedback = true

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
        case .about:
          aboutSettings
        }
      }
      .formStyle(.grouped)
      .scrollContentBackground(.hidden)
    }
    .frame(minWidth: 560, idealWidth: 620, maxWidth: 760, minHeight: 440, idealHeight: 500)
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
      Toggle("VoiceOver 교정 알림", isOn: $showCorrectionFeedback)
    }

    Section("권한") {
      PermissionRow(
        title: "입력 모니터링",
        explanation: "물리 키 위치를 읽어 현재 단어만 메모리에서 판별합니다.",
        isGranted: model.permissions.canMonitorInput,
        request: model.requestInputMonitoring,
        openSettings: model.openInputMonitoringSettings
      )
      PermissionRow(
        title: "손쉬운 사용",
        explanation: "교정 직전 포커스와 범위를 확인하고 해당 단어만 바꿉니다.",
        isGranted: model.permissions.isAccessibilityTrusted,
        request: model.requestAccessibility,
        openSettings: model.openAccessibilitySettings
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
      Label("터미널·IDE·원격 데스크톱", systemImage: "terminal")
      Text("지원 여부를 확신할 수 없으면 교정하지 않습니다. 클립보드 fallback도 사용하지 않습니다.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var shortcutSettings: some View {
    Section("전역 단축키") {
      LabeledContent("마지막 단어 수동 변환", value: "지정 안 됨")
      LabeledContent("마지막 교정 되돌리기", value: "지정 안 됨")
      Text("충돌을 피하기 위해 기본 전역 단축키를 강제로 등록하지 않습니다. 단축키 기록과 충돌 검사는 로컬 설정에만 저장됩니다.")
        .font(.footnote)
        .foregroundStyle(.secondary)
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
    }
  }
}
