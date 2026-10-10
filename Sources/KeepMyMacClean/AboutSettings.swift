import AppKit
import SwiftUI

// Settings' About and Updates sections. GitTree and Vibe Notepad show the same rows.

/// Version, build (commit count · commit), configuration and build time, with Copy Version Info for bug reports.
struct AboutSection: View {
    var body: some View {
        Section("About \(BuildInfo.name)") {
            LabeledContent("Version", value: BuildInfo.version)
            LabeledContent("Build") {
                Text(verbatim: BuildInfo.buildDescription)
                    .monospacedDigit()
            }
            LabeledContent("Configuration") {
                Text(BuildInfo.configuration)
                    .foregroundStyle(BuildInfo.isDebug ? Palette.orange : Palette.secondaryText)
                    .help(BuildInfo.isDebug
                          ? "A development build (swift build, or CONFIG=debug scripts/build-app.sh)."
                          : "An optimized build, as built by scripts/build-app.sh or downloaded from GitHub.")
            }
            LabeledContent("Built") {
                if let date = BuildInfo.date {
                    Text(date, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                } else {
                    Text("Unknown")
                }
            }
            HStack {
                Link("Source on GitHub", destination: AppUpdater.repositoryURL)
                Spacer()
                Button("Copy Version Info") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(BuildInfo.summary, forType: .string)
                }
            }
        }
        .textSelection(.enabled)
    }
}

/// What the last update check found, with Check Now, or Download when there's a newer version.
struct UpdatesSection: View {
    private let updater = AppUpdater.shared

    var body: some View {
        Section {
            LabeledContent {
                if updater.isChecking {
                    ProgressView()
                        .controlSize(.small)
                } else if let release = updater.available {
                    Button("Download") { updater.download(release) }
                } else {
                    Button("Check Now") { Task { await updater.check() } }
                }
            } label: {
                Text(title)
                Text(detail)
                    .foregroundStyle(Palette.secondaryText)
            }
            if let release = updater.available {
                Link("Release Notes", destination: release.pageURL)
            }
        } header: {
            Text("Updates")
        } footer: {
            Text("KeepMyMacClean asks GitHub for the newest release when it starts and once a day while it runs. Check for Updates, at the bottom of the menu bar window, asks any time.")
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)
        }
    }

    private var title: String {
        if updater.isChecking { return "Checking for updates…" }
        if let release = updater.available { return "KeepMyMacClean \(release.version) is available" }
        if updater.failure != nil { return "Couldn't check for updates" }
        if updater.lastChecked != nil { return "KeepMyMacClean is up to date" }
        return "Not checked yet"
    }

    private var detail: String {
        if let release = updater.available {
            let released = release.publishedAt.map { " · released \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
            return "You have \(BuildInfo.version)\(released)"
        }
        if let failure = updater.failure { return failure }
        if let checked = updater.lastChecked {
            let when = "Checked \(checked.formatted(.relative(presentation: .named)))"
            return updater.latest == nil ? "\(when) · no releases yet" : when
        }
        return BuildInfo.isDebug ? "Debug builds check only when you ask." : "KeepMyMacClean checks when it starts."
    }
}
