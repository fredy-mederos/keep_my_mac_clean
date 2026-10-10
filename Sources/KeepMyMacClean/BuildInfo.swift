import Foundation

/// What Settings → About shows about this copy of Vibe Clean. scripts/build-app.sh stamps the build number (the
/// number of commits), the commit and the build time into Info.plist; `swift run` builds have none of them.
enum BuildInfo {
    private static var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    static let name = "Vibe Clean"

    /// `0.4.0`, or "–" when run with `swift run`.
    static var version: String { info["CFBundleShortVersionString"] as? String ?? "–" }

    /// The number of commits it was built from.
    static var build: String { info["CFBundleVersion"] as? String ?? "–" }

    /// The short hash it was built from.
    static var commit: String? {
        stampedCommit.map { $0.hasSuffix("+") ? String($0.dropLast()) : $0 }
    }

    /// It was built with changes that weren't committed yet (stamped as a `+` after the hash).
    static var hasLocalChanges: Bool { stampedCommit?.hasSuffix("+") ?? false }

    private static var stampedCommit: String? { info["KMMCGitCommit"] as? String }

    /// When it was built: the stamped time, or else when the executable was linked.
    static var date: Date? {
        if let stamp = info["KMMCBuildDate"] as? String, let date = try? Date(stamp, strategy: .iso8601) { return date }
        guard let executable = Bundle.main.executableURL else { return nil }
        return (try? executable.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    static var isDebug: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// "Debug" or "Release".
    static var configuration: String { isDebug ? "Debug" : "Release" }

    /// `9 · fee5ec6` or `9 · fee5ec6 + local changes`.
    static var buildDescription: String {
        var text = build
        if let commit { text += " · \(commit)" }
        if hasLocalChanges { text += " + local changes" }
        return text
    }

    /// For pasting into a bug report: `Vibe Clean 1.2.0 (20, fee5ec6), Release, built 2026-10-11 09:22`.
    static var summary: String {
        let details = [build, commit.map { hasLocalChanges ? $0 + "+" : $0 }].compactMap { $0 }.joined(separator: ", ")
        let built = date.map { ", built " + $0.formatted(.iso8601.year().month().day().dateSeparator(.dash)) + " "
            + $0.formatted(date: .omitted, time: .shortened) } ?? ""
        return "\(name) \(version) (\(details)), \(configuration)\(built)"
    }
}
