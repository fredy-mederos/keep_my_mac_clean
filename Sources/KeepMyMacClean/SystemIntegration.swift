import Foundation
import ServiceManagement
import UserNotifications

/// Notifications and login items only work from a real .app bundle, not from `swift run`.
private var isBundledApp: Bool {
    Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
}

/// Version details stamped into Info.plist by scripts/build-app.sh.
enum AppVersion {
    private static var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    static var isStamped: Bool { info["KMMCGitCommit"] != nil }
    static var version: String { info["CFBundleShortVersionString"] as? String ?? "dev" }
    /// Number of commits in the build's history.
    static var build: String { info["CFBundleVersion"] as? String ?? "0" }
    /// Short commit hash, with "-dirty" when built with uncommitted changes.
    static var commit: String? { info["KMMCGitCommit"] as? String }
    static var buildDate: Date? {
        (info["KMMCBuildDate"] as? String).flatMap { try? Date($0, strategy: .iso8601) }
    }

    /// "Version 0.4 (build 9 · fee5ec6)", or "Development build" when run with `swift run`.
    static var summary: String {
        guard isStamped, let commit else { return "Development build" }
        return "Version \(version) (build \(build) · \(commit))"
    }
}

enum Notifier {
    static func requestAuthorization() {
        guard isBundledApp else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String) {
        guard isBundledApp else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: "low-space", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

enum LoginItem {
    static var isAvailable: Bool { isBundledApp }

    static var isEnabled: Bool {
        isBundledApp && SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard isBundledApp else { return }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
