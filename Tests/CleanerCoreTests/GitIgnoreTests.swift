import Foundation
import Testing
@testable import CleanerCore

@Suite struct GitIgnoreTests {
    func git(_ repo: URL, _ arguments: [String]) throws {
        let output = try CommandRunner.run("/usr/bin/git", ["-C", repo.path, "-c", "user.email=t@t", "-c", "user.name=t"] + arguments)
        #expect(output.status == 0, "git \(arguments.joined(separator: " ")): \(output.stderr)")
    }

    /// An Android-style project: build/ ignored, .kotlin/ not in .gitignore, and .gradle/ ignored by a
    /// pattern but with a file force-added (committed by mistake).
    func androidRepo(in home: TestHome) throws -> URL {
        let repo = try home.folder("dev/app")
        try home.file("dev/app/settings.gradle.kts")
        try home.file("dev/app/.gitignore", contents: "build/\n.gradle/\n")
        try home.file("dev/app/build/out.bin", bytes: 2_000_000)
        try home.file("dev/app/.kotlin/sessions/x.bin", bytes: 2_000_000)
        try home.file("dev/app/.gradle/8.13/state.bin", bytes: 2_000_000)
        try git(repo, ["init", "-q"])
        try git(repo, ["add", "settings.gradle.kts", ".gitignore"])
        try git(repo, ["add", "-f", ".gradle/8.13/state.bin"])
        try git(repo, ["commit", "-q", "-m", "init"])
        return repo
    }

    @Test func splitsFoldersByWhatGitSays() throws {
        let home = try TestHome()
        let repo = try androidRepo(in: home)
        let folders = ProjectArtifacts.findArtifacts(in: repo)
        #expect(Set(folders.map(\.lastPathComponent)) == ["build", ".kotlin", ".gradle"])

        let result = GitIgnoreCheck.check(folders, in: repo)
        #expect(result.isRepository)
        #expect(result.ignored.map(\.lastPathComponent) == ["build"])
        let skipped = Dictionary(uniqueKeysWithValues: result.skipped.map { ($0.url.lastPathComponent, $0.reason) })
        #expect(skipped == [".kotlin": "not ignored by git", ".gradle": "1 file tracked in git"])
    }

    @Test func folderWhoseFilesAreAllIgnoredCounts() throws {
        let home = try TestHome()
        let repo = try home.folder("dev/xamarin")
        try home.file("dev/xamarin/App.sln")
        try home.file("dev/xamarin/.gitignore", contents: "*.dll\n*.nupkg\n")
        try home.file("dev/xamarin/packages/Forms/lib/Forms.dll")
        try home.file("dev/xamarin/packages/Forms/Forms.nupkg")
        try home.file("dev/xamarin/App/App.csproj")
        try home.file("dev/xamarin/App/obj/project.assets.json")   // not covered by the patterns
        try git(repo, ["init", "-q"])
        let result = GitIgnoreCheck.check(ProjectArtifacts.findArtifacts(in: repo), in: repo)
        #expect(result.ignored.map(\.lastPathComponent) == ["packages"])
        #expect(result.skipped.map(\.url.lastPathComponent) == ["obj"])
        #expect(result.skipped.first?.reason == "not ignored by git")
    }

    @Test func gitignoredDataIsNeverOffered() throws {
        // Git only removes folders from the list, never adds them: ignored app data stays untouched.
        let home = try TestHome()
        let repo = try home.folder("dev/monitor")
        try home.file("dev/monitor/package.json")
        try home.file("dev/monitor/.gitignore", contents: "dist/\ndata/\nraw/\ncaptures/\nuploads/\n.claude/\n.env\n*.sqlite\n")
        try home.file("dev/monitor/dist/index.js", bytes: 2_000_000)
        for path in ["data/incidents.sqlite", "raw/export.csv", "captures/screen.png", "uploads/a.jpg", ".claude/worktrees/x/main.swift", ".env"] {
            try home.file("dev/monitor/\(path)", bytes: 2_000_000)
        }
        try git(repo, ["init", "-q"])

        let context = ScanContext(home: home.url, projectLocations: [home.path("dev")], runsSystemCommands: true)
        let item = try #require(ProjectsScanner().items(in: context).first)
        guard case .removePaths(let urls) = item.action else { Issue.record("expected paths"); return }
        #expect(urls.map(\.lastPathComponent) == ["dist"])
        #expect(item.skipped.isEmpty)
    }

    @Test func outsideGitNothingIsConfirmed() throws {
        let home = try TestHome()
        try home.file("dev/loose/package.json")
        try home.file("dev/loose/node_modules/x.js")
        let result = GitIgnoreCheck.check(ProjectArtifacts.findArtifacts(in: home.path("dev/loose")), in: home.path("dev/loose"))
        #expect(!result.isRepository)
        #expect(result.ignored.isEmpty)
    }

    @Test func scannerOnlyDeletesConfirmedFolders() throws {
        let home = try TestHome()
        _ = try androidRepo(in: home)
        try home.file("dev/loose/package.json")
        try home.file("dev/loose/node_modules/x.js", bytes: 2_000_000)

        let context = ScanContext(home: home.url, projectLocations: [home.path("dev")], runsSystemCommands: true)
        let items = Dictionary(uniqueKeysWithValues: ProjectsScanner().items(in: context).map { ($0.title, $0) })

        let app = try #require(items["app"])
        #expect(app.safety == .safe)
        #expect(app.checkedWithGit)
        guard case .removePaths(let urls) = app.action else { Issue.record("expected paths"); return }
        #expect(urls.map(\.lastPathComponent) == ["build"])
        #expect(Set(app.skipped.map(\.url.lastPathComponent)) == [".kotlin", ".gradle"])

        let loose = try #require(items["loose"])
        #expect(loose.safety == .review)
        #expect(!loose.checkedWithGit)
        #expect(loose.reason?.contains("isn't a git repository") == true)
    }

    @Test func projectWithNothingIgnoredIsNotListed() throws {
        let home = try TestHome()
        let repo = try home.folder("dev/web")
        try home.file("dev/web/package.json")
        try home.file("dev/web/node_modules/x.js", bytes: 2_000_000)
        try git(repo, ["init", "-q"])
        let context = ScanContext(home: home.url, projectLocations: [home.path("dev")], runsSystemCommands: true)
        #expect(ProjectsScanner().items(in: context).isEmpty)
    }
}
