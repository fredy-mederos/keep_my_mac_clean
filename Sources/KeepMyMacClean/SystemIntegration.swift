import AppKit
import Foundation
import ServiceManagement
import UserNotifications

/// Notifications and login items only work from a real .app bundle, not from `swift run`.
private var isBundledApp: Bool {
    Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
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

#if DEBUG
/// Debug builds: `-OpenMenuBarWindow YES` opens the menu bar window at launch, as clicking the menu bar item
/// does, so it can be checked and captured without a click.
@MainActor
enum MenuBarWindow {
    static func openIfAsked() {
        guard UserDefaults.standard.bool(forKey: "OpenMenuBarWindow") else { return }
        Task {
            try? await Task.sleep(for: .seconds(1))
            for window in NSApp.windows where window.className.contains("StatusBarWindow") {
                if let button = window.contentView.flatMap(statusButton(in:)) {
                    button.performClick(nil)
                    return
                }
            }
        }
    }

    private static func statusButton(in view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton { return button }
        return view.subviews.lazy.compactMap(statusButton(in:)).first
    }
}
#endif
