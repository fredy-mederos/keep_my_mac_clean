import SwiftUI

@main
struct KeepMyMacCleanApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        let symbol = model.isLowOnSpace ? "exclamationmark.triangle.fill" : "internaldrive"
        Text("\(Image(systemName: symbol)) \(model.menuBarText)")
            .accessibilityLabel("\(model.menuBarText) free")
    }
}
