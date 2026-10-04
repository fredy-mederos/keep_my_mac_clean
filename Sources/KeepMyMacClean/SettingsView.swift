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
                    Text("No project folders yet.").foregroundStyle(.secondary)
                }
                ForEach(model.settings.projectLocations, id: \.self) { path in
                    HStack {
                        Image(systemName: "folder").foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
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

            Section("Alerts") {
                Toggle("Notify me when free space is low", isOn: $model.settings.notifyOnLowSpace)
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
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 480)
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
