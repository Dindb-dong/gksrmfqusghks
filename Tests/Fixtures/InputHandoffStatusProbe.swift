// Read only HanKey's local-test scalar status; no text access, events or source changes.
import AppKit
import Foundation

@main
struct InputHandoffStatusProbe {
  @MainActor static func main() {
    NSApplication.shared.setActivationPolicy(.prohibited)
    if CommandLine.arguments.contains("--frontmost") {
      print(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1)
      return
    }
    let center = DistributedNotificationCenter.default()
    let requestID = UUID().uuidString
    var reply: [String: String]?
    let token = center.addObserver(
      forName: Notification.Name("com.dindbdong.hankey.handoff-status.response"),
      object: requestID, queue: .main
    ) { notification in
      MainActor.assumeIsolated {
        guard let info = notification.userInfo,
          let stage = info["stage"] as? String, let outcome = info["outcome"] as? String,
          stage.count < 64, outcome.count < 64
        else { return }
        reply = ["stage": stage, "outcome": outcome]
      }
    }
    defer { center.removeObserver(token) }
    center.postNotificationName(
      Notification.Name("com.dindbdong.hankey.handoff-status.request"), object: requestID,
      userInfo: nil, deliverImmediately: true)
    let deadline = Date().addingTimeInterval(2)
    while reply == nil, Date() < deadline {
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    guard let reply,
      let data = try? JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys]),
      let text = String(data: data, encoding: .utf8)
    else {
      print("No local-test status reply")
      exit(1)
    }
    print(text)
  }
}
