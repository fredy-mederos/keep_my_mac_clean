import Foundation
import Testing
@testable import CleanerCore

@Suite struct ProjectProfileTests {
    @Test func detectsStacks() throws {
        let home = try TestHome()
        try home.file("next/package.json", contents: #"{"dependencies": {"next": "15", "react": "19"}}"#)
        try home.file("rn/package.json", contents: #"{"dependencies": {"react-native": "0.80"}}"#)
        try home.file("plain/package.json", contents: #"{"name": "x"}"#)
        try home.file("flutter/pubspec.yaml", contents: "name: app\nflutter:\n  uses-material-design: true\n")
        try home.file("android/settings.gradle.kts")
        try home.file("android/app/build.gradle.kts", contents: #"plugins { id("com.android.application") }"#)
        try home.file("gradle/build.gradle")
        try home.folder("ios/App.xcodeproj")
        try home.folder("unity/Assets")
        try home.folder("unity/ProjectSettings")

        let stacks = ["next", "rn", "plain", "flutter", "android", "gradle", "ios", "unity"].map {
            ProjectProfiler.stack(of: home.path($0))
        }
        #expect(stacks == ["Next.js", "React Native", "Node.js", "Flutter", "Android", "Gradle", "Xcode", "Unity"])
    }

    @Test func readsTheFirstRealParagraphOfAReadme() {
        let readme = """
            # PokeQuiz

            [![Build](https://x/badge.svg)](https://x)

            ```bash
            npm run dev
            ```

            PokeQuiz es una app web construida con [Next.js](https://nextjs.org) que reúne un hub de **minijuegos**.
            Desplegada en Vercel.

            ## Desarrollo
            """
        #expect(ProjectProfiler.firstParagraph(ofMarkdown: readme)
                == "PokeQuiz es una app web construida con Next.js que reúne un hub de minijuegos. Desplegada en Vercel.")
    }

    @Test func ignoresTemplateDescriptions() throws {
        let home = try TestHome()
        try home.file("a/pubspec.yaml", contents: "name: a\ndescription: \"A new Flutter project.\"\nflutter:\n")
        try home.file("a/README.md", contents: "# a\n\nA new Flutter project.\n\n## Getting Started\n")
        try home.file("b/package.json", contents: #"{"description": "Local-first planning board for Jira releases"}"#)
        try home.file("c/package.json", contents: "{}")
        try home.file("c/README.md", contents: "This is a [Next.js](https://nextjs.org) project bootstrapped with create-next-app.\n")
        #expect(ProjectProfiler.description(of: home.path("a")) == nil)
        #expect(ProjectProfiler.description(of: home.path("b")) == "Local-first planning board for Jira releases")
        #expect(ProjectProfiler.description(of: home.path("c")) == nil)

        try home.file("d/README.md", contents: "# Tracker\n\nSample: https://github.com/wkda/app/blob/develop/Tracking.kt\n")
        #expect(ProjectProfiler.description(of: home.path("d")) == nil)
    }

    @Test func plainLineFallsBackToStackAndLatestCommit() {
        var profile = ProjectProfile(name: "grasshopper-translator", stack: "Node.js", description: nil)
        #expect(profile.plainBlurb == "Node.js project")
        profile.lastCommitSubject = "Initial demo reader prototype"
        #expect(profile.plainBlurb == #"Node.js project · last commit: "Initial demo reader prototype""#)
    }

    @Test func modelOnlyRunsWhenThereIsSomethingToCondenseOrTranslate() {
        let none = ProjectProfile(name: "x", stack: "Flutter", description: nil)
        let shortName = ProjectProfile(name: "x", stack: "Flutter", description: "Mapa C19 Application.")
        #expect(!shortName.wantsModelSummary)
        let shortEnglish = ProjectProfile(name: "x", stack: "React", description: "A todo list app for teams.")
        let spanish = ProjectProfile(name: "x", stack: "React", description: "Prototipo de escape room web inspirado en juegos tipo Rusty Lake.")
        let long = ProjectProfile(name: "x", stack: "React", description: String(repeating: "A planning board for releases and workload. ", count: 3))
        #expect(!none.wantsModelSummary)
        #expect(!shortEnglish.wantsModelSummary)
        #expect(spanish.wantsModelSummary)
        #expect(long.wantsModelSummary)
    }

    @Test func promptNeverContainsDates() {
        let profile = ProjectProfile(
            name: "pokequiz", stack: "Next.js", description: "PokeQuiz es una app web.",
            lastCommit: Date(timeIntervalSince1970: 1_777_000_000), lastCommitSubject: "Add sprite atlas", commitCount: 57
        )
        #expect(!profile.prompt.contains("2026"))
        #expect(!profile.prompt.contains("57"))
        #expect(profile.prompt.contains("Latest commit message: Add sprite atlas"))
        #expect(profile.activity()?.hasSuffix("· 57 commits") == true)
    }

    @Test func readsGitHistory() throws {
        let home = try TestHome()
        let project = try home.folder("repo")
        try home.file("repo/package.json", contents: #"{"description": "Tiny test project for the profiler"}"#)
        for args in [["init", "-q"], ["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "First"],
                     ["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "Second change"]] {
            _ = try CommandRunner.run("/usr/bin/git", ["-C", project.path] + args)
        }
        let profile = ProjectProfiler.profile(of: project)
        #expect(profile.commitCount == 2)
        #expect(profile.lastCommitSubject == "Second change")
        #expect(profile.lastCommit != nil)
        #expect(profile.description == "Tiny test project for the profiler")
    }
}
