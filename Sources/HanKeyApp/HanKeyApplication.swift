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
  @ObservationIgnored private var observationRuntime: InputObservationRuntime?

  init() {
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
    case .wordCompleted:
      // F05 consumes completed words. F04 intentionally stores no typed content.
      break
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
        Text("자동 교정은 명시적으로 켠 뒤에만 입력을 관찰합니다. 텍스트 교체는 다음 기능 단계에서 연결됩니다.")
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
