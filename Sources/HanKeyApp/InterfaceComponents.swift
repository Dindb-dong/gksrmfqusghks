import SwiftUI

struct StatusHeader: View {
  let status: OperationalStatus

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: status.symbol)
        .font(.title2)
        .foregroundStyle(status == .eventTapError ? Color.red : Color.accentColor)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text(status.title)
          .font(.headline)
        Text(status.detail)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("operational-status")
  }
}

struct PermissionRow: View {
  let title: String
  let explanation: String
  let isGranted: Bool
  let request: () -> Void
  let openSettings: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Label(
          title,
          systemImage: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle"
        )
        .foregroundStyle(isGranted ? Color.green : Color.primary)
        Spacer()
        Text(isGranted ? "허용됨" : "필요함")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Text(explanation)
        .font(.footnote)
        .foregroundStyle(.secondary)

      if !isGranted {
        HStack {
          Button("권한 요청", action: request)
          Button("시스템 설정 열기", action: openSettings)
        }
        .controlSize(.small)
      }
    }
    .accessibilityElement(children: .contain)
  }
}

struct LocalOnlyDisclosure: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("이 Mac 안에서만 처리", systemImage: "lock.laptopcomputer")
        .font(.headline)
      Text("키 입력, 교정 전후 단어, 선택 텍스트는 네트워크로 전송하거나 디스크에 기록하지 않습니다.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Text("비밀번호 필드와 보안 입력에서는 메모리 버퍼도 즉시 비웁니다.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("local-only-disclosure")
  }
}
