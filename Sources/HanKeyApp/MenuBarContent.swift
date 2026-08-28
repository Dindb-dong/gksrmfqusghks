import AppKit
import SwiftUI

struct MenuBarContent: View {
  @Bindable var model: AppModel
  @Environment(\.openSettings) private var openSettings
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    StatusHeader(status: model.operationalStatus)
      .padding(.vertical, 4)

    Toggle(
      "자동 교정",
      isOn: Binding(
        get: { model.isCorrectionEnabled },
        set: { model.setCorrectionEnabled($0) }
      )
    )
    .disabled(!model.isCorrectionEnabled && !model.permissions.isReady)
    .accessibilityHint(
      model.permissions.isReady ? "키 입력 관찰과 자동 교정을 전환합니다." : "먼저 두 권한을 허용해야 합니다."
    )

    Text("최근 동작: \(model.correctionActivity.title)")
      .foregroundStyle(.secondary)

    Divider()

    Button("선택 영역 또는 마지막 단어 변환") {
      model.convertSelectionOrLastWord()
    }
    .disabled(!model.canUseManualCorrection)

    Button("마지막 교정 되돌리기") {
      model.undoLastCorrection()
    }
    .disabled(!model.canUndo)

    if model.canRememberLastUndoAsNever {
      Button("방금 되돌린 교정을 다시 변환하지 않기") {
        model.rememberLastUndoAsNever()
      }
    }

    Divider()

    if !model.permissions.hasRequiredPermissions {
      Button("권한 설정 확인…") {
        openSettingsInFront()
      }
    }

    Button("권한 상태 새로고침") {
      model.refreshPermissions()
    }

    Button("시작 안내 다시 보기…") {
      UserDefaults.standard.set(false, forKey: "onboardingCompleted")
      openWindow(id: "onboarding")
    }

    Button("설정…") {
      openSettingsInFront()
    }
    .keyboardShortcut(",", modifiers: .command)

    Divider()

    Button("한글변환 종료") {
      NSApplication.shared.terminate(nil)
    }
    .keyboardShortcut("q", modifiers: .command)
  }

  private func openSettingsInFront() {
    SettingsWindowPresenter.open {
      openSettings()
    }
  }
}
