import Foundation
import NaturalLanguage

/// What a project is and how active it is, read from its own files and git history.
/// The activity is always computed here; a language model may only describe what the project is.
public struct ProjectProfile: Sendable, Hashable {
    public var name: String
    /// "Next.js", "Flutter", "Android", "Xcode"...
    public var stack: String?
    /// The project's own description (package.json, pubspec.yaml or the README), when it isn't template text.
    public var description: String?
    public var lastCommit: Date?
    public var lastCommitSubject: String?
    public var commitCount: Int?

    /// "Last commit 5 months ago · 57 commits", or nil without git history.
    public func activity(now: Date = Date()) -> String? {
        guard let lastCommit else { return nil }
        var text = "Last commit \(lastCommit.formatted(.relative(presentation: .named, unitsStyle: .wide)))"
        if let commitCount { text += commitCount == 1 ? " · 1 commit" : " · \(commitCount) commits" }
        return text
    }

    /// One line without any model: the description if there is one, otherwise the stack and the latest commit.
    public var plainBlurb: String? {
        if let description { return description.count > 140 ? String(description.prefix(137)) + "…" : description }
        let base = stack.map { "\($0) project" }
        guard let subject = lastCommitSubject else { return base }
        return (base.map { "\($0) · " } ?? "") + "last commit: \"\(subject)\""
    }

    /// Only worth asking a model when there's a description to condense or translate. Without one, a model
    /// can only guess from the folder name, which tested worse than the plain line.
    public var wantsModelSummary: Bool {
        guard let description else { return false }
        if description.count > 80 { return true }
        // Language detection is unreliable on short names like "Mapa C19 Application", so require some text
        // and a confident guess before translating.
        guard description.count >= 30 else { return false }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(description)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first else { return false }
        return language != .english && confidence >= 0.8
    }

    /// The facts a language model gets: no dates, so it can't misjudge activity.
    public var prompt: String {
        var lines = ["Project folder name: \(name)"]
        if let stack { lines.append("Technology: \(stack)") }
        if let description { lines.append("Description from the project: \(description)") }
        if let lastCommitSubject { lines.append("Latest commit message: \(lastCommitSubject)") }
        return lines.joined(separator: "\n")
    }
}

public enum ProjectProfiler {
    public static func profile(of project: URL, runsGit: Bool = true) -> ProjectProfile {
        var profile = ProjectProfile(name: project.lastPathComponent, stack: stack(of: project), description: description(of: project))
        if runsGit, FileInfo.exists(project.appendingPathComponent(".git")) {
            if let output = try? CommandRunner.run("/usr/bin/git", ["-C", project.path, "log", "-1", "--format=%ct%x1f%s"], timeout: 5),
               output.status == 0 {
                let parts = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\u{1f}", maxSplits: 1)
                if let seconds = parts.first.flatMap({ TimeInterval($0) }) {
                    profile.lastCommit = Date(timeIntervalSince1970: seconds)
                }
                if parts.count > 1 { profile.lastCommitSubject = String(parts[1]) }
            }
            if let output = try? CommandRunner.run("/usr/bin/git", ["-C", project.path, "rev-list", "--count", "HEAD"], timeout: 5),
               output.status == 0 {
                profile.commitCount = Int(output.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return profile
    }

    // MARK: Stack

    static func stack(of project: URL) -> String? {
        let names = Set(FileInfo.childNames(of: project))
        if names.contains("Assets"), names.contains("ProjectSettings") { return "Unity" }
        if names.contains("pubspec.yaml") {
            let pubspec = (try? String(contentsOf: project.appendingPathComponent("pubspec.yaml"), encoding: .utf8)) ?? ""
            return pubspec.contains("flutter:") ? "Flutter" : "Dart"
        }
        if names.contains("package.json") { return nodeStack(project.appendingPathComponent("package.json")) }
        if !names.isDisjoint(with: ProjectArtifacts.gradleFiles) {
            let isAndroid = FileInfo.exists(project.appendingPathComponent("app/src/main/AndroidManifest.xml"))
                || ["build.gradle", "build.gradle.kts", "app/build.gradle", "app/build.gradle.kts"].contains { file in
                    ((try? String(contentsOf: project.appendingPathComponent(file), encoding: .utf8)) ?? "").contains("com.android")
                }
            return isAndroid ? "Android" : "Gradle"
        }
        if names.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) { return "Xcode" }
        if names.contains("Package.swift") { return "Swift package" }
        if names.contains("Cargo.toml") { return "Rust" }
        if names.contains("go.mod") { return "Go" }
        if names.contains("pom.xml") { return "Java (Maven)" }
        return nil
    }

    static func nodeStack(_ packageJSON: URL) -> String {
        guard let data = try? Data(contentsOf: packageJSON),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return "Node.js" }
        let dependencies = Set(["dependencies", "devDependencies"].flatMap { (json[$0] as? [String: Any])?.keys ?? [:].keys })
        let frameworks: [(String, String)] = [
            ("next", "Next.js"), ("expo", "Expo"), ("react-native", "React Native"), ("nuxt", "Nuxt"),
            ("@sveltejs/kit", "SvelteKit"), ("electron", "Electron"), ("@angular/core", "Angular"),
            ("vue", "Vue"), ("react", "React"), ("svelte", "Svelte"), ("express", "Express"),
            ("@nestjs/core", "NestJS"), ("remotion", "Remotion"),
        ]
        return frameworks.first { dependencies.contains($0.0) }?.1 ?? "Node.js"
    }

    // MARK: Description

    /// Generated templates say nothing about the project.
    static let boilerplate = [
        "a new flutter project", "a new flutter package", "bootstrapped with create-next-app",
        "bootstrapped with create react app", "this template should help get you started",
        "this is a next.js project", "getting started", "a new dart project",
    ]

    static func isBoilerplate(_ text: String) -> Bool {
        let lower = text.lowercased()
        return boilerplate.contains { lower.contains($0) }
    }

    static func description(of project: URL) -> String? {
        var candidates: [String] = []
        if let data = try? Data(contentsOf: project.appendingPathComponent("package.json")),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let description = json["description"] as? String {
            candidates.append(description)
        }
        if let pubspec = try? String(contentsOf: project.appendingPathComponent("pubspec.yaml"), encoding: .utf8),
           let match = pubspec.firstMatch(of: /(?m)^description:\s*["']?(.+?)["']?\s*$/) {
            candidates.append(String(match.1))
        }
        for name in ["README.md", "readme.md", "README.MD", "Readme.md", "README"] {
            if let readme = try? String(contentsOf: project.appendingPathComponent(name), encoding: .utf8) {
                if let paragraph = firstParagraph(ofMarkdown: readme) { candidates.append(paragraph) }
                break
            }
        }
        return candidates
            .map(clean)
            .first { $0.count >= 12 && !isBoilerplate($0) }
    }

    /// Without bare links: a README line like "Sample: https://github.com/…" says nothing about the project.
    static func clean(_ text: String) -> String {
        text.replacing(/https?:\/\/\S+/, with: "")
            .replacing(/\s{2,}/, with: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":-–—")))
    }

    /// The first prose paragraph of a README: no headings, badges, images, code blocks, tables or lists.
    static func firstParagraph(ofMarkdown text: String) -> String? {
        var paragraph: [String] = []
        var inCode = false
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { inCode.toggle(); continue }
            if inCode { continue }
            let skippable = line.hasPrefix("#") || line.hasPrefix("![") || line.hasPrefix("[![") || line.hasPrefix("<")
                || line.hasPrefix("|") || line.hasPrefix("-") || line.hasPrefix("*") || line.hasPrefix(">") || line.hasPrefix("=")
            if line.isEmpty || skippable {
                if !paragraph.isEmpty { break }
                continue
            }
            paragraph.append(line)
        }
        guard !paragraph.isEmpty else { return nil }
        // Drop markdown links and emphasis so the text reads plainly.
        let joined = paragraph.joined(separator: " ")
            .replacing(/\[([^\]]+)\]\([^)]*\)/) { String($0.1) }
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
        return String(joined.prefix(600))
    }
}
