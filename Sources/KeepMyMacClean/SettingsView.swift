import CleanerCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?
    @State private var isDiscovering = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                if model.settings.projectLocations.isEmpty {
                    Text("No project folders yet.").foregroundStyle(Palette.secondaryText)
                }
                ForEach(model.settings.projectLocations, id: \.self) { path in
                    HStack {
                        Image(systemName: "folder").foregroundStyle(Palette.secondaryText)
                        Text(PathFormat.abbreviated(URL(fileURLWithPath: path)))
                        Spacer()
                        Button {
                            model.removeProjectLocation(path)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Stop scanning this folder")
                    }
                }
                HStack {
                    Button("Add folder…", action: addFolder)
                    Button(isDiscovering ? "Searching…" : "Find projects again") {
                        Task {
                            isDiscovering = true
                            await model.discoverProjects()
                            isDiscovering = false
                            await model.rescan()
                        }
                    }
                    .disabled(isDiscovering)
                }
            } header: {
                Text("Project folders")
            } footer: {
                Text("Build folders of the projects in these places show up under Project build folders. They were found automatically on first launch.")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }

            Section("Cleaning") {
                Picker("Treat projects as inactive after", selection: $model.settings.inactiveAfterMonths) {
                    ForEach([1, 3, 6, 12], id: \.self) { months in
                        Text(months == 1 ? "1 month" : "\(months) months").tag(months)
                    }
                }
                Picker("List my files larger than", selection: $model.settings.largeFileThresholdMB) {
                    ForEach([100, 250, 500, 1000, 2000], id: \.self) { megabytes in
                        Text(ByteFormat.short(Int64(megabytes) * 1_000_000)).tag(megabytes)
                    }
                }
                .onChange(of: model.settings.largeFileThresholdMB) {
                    Task { await model.rescan() }
                }
            }

            Section {
                let availability = SmartSuggestions.availability
                Toggle("Smarter suggestions (on-device AI)", isOn: $model.settings.smartSuggestions)
                    .disabled(availability != .available)
                if case .unavailable(let reason) = availability {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
            } header: {
                Text("Suggestions")
            } footer: {
                Text("Apple Intelligence, on this Mac, writes a one-line suggestion for each of your large files and downloads, and sums up projects whose README is long or not in English. It only changes text; what cleaning does stays the same.")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }

            Section("Alerts") {
                Toggle("Notify me when free space is low", isOn: $model.settings.notifyOnLowSpace)
                Toggle("Weekly summary of what changed", isOn: $model.settings.weeklySummary)
                Stepper("Alert below \(model.settings.lowSpaceThresholdGB) GB", value: $model.settings.lowSpaceThresholdGB, in: 5...200, step: 5)
            }

            Section("General") {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .disabled(!LoginItem.isAvailable)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LoginItem.setEnabled(enabled)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = LoginItem.isEnabled
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(Palette.red)
                }
            }

            Section("About") {
                LabeledContent("KeepMyMacClean") {
                    Text(AppVersion.summary)
                        .textSelection(.enabled)
                }
                if let date = AppVersion.buildDate {
                    LabeledContent("Built", value: date.formatted(date: .abbreviated, time: .shortened))
                }
                Link("Source on GitHub", destination: URL(string: "https://github.com/fredy-mederos/keep_my_mac_clean")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 620)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose a folder that contains your projects"
        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url {
            model.addProjectLocation(url)
        }
    }
}
