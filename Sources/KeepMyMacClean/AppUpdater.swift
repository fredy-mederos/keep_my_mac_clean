import AppKit
import Observation

/// Checks GitHub for a newer KeepMyMacClean: a few seconds after launch (at most once an hour), once a day while it
/// runs, and whenever you ask (Check for Updates at the bottom of the menu bar window, Settings → Updates). Each
/// check is one request (`ReleaseFeed`); nothing is downloaded until you choose to. A newer version shows as Update
/// Available at the bottom of the menu bar window and in Settings.
@MainActor @Observable
final class AppUpdater {
    static let shared = AppUpdater()

    /// KeepMyMacClean's repository: its source, and the releases it checks.
    static let repository = "fredy-mederos/keep_my_mac_clean"
    static var repositoryURL: URL { URL(string: "https://github.com/\(repository)")! }

    /// The newest release GitHub named at the last check, kept between launches; nil when there's none yet.
    private(set) var latest: Release?
    /// When GitHub last answered.
    private(set) var lastChecked: Date?
    private(set) var isChecking = false
    /// Why the last check failed, until one succeeds.
    private(set) var failure: String?

    /// The newest release, when it's newer than this copy of KeepMyMacClean.
    var available: Release? {
        guard let latest, VersionNumber.isValid(BuildInfo.version),
              VersionNumber.isVersion(BuildInfo.version, olderThan: latest.version) else { return nil }
        return latest
    }

    @ObservationIgnored private var feed = ReleaseFeed(repository: repository, diskImageName: "KeepMyMacClean.dmg")
    @ObservationIgnored private let defaults = UserDefaults.standard
    /// False while a debug build tries another repository, so that one's releases aren't kept.
    @ObservationIgnored private var keepsState = true
    @ObservationIgnored private var lastAttempt: Date?
    @ObservationIgnored private var schedule: Task<Void, Never>?

    private enum Key {
        static let latest = "updates.latestRelease"
        static let lastChecked = "updates.lastChecked"
        static let lastAttempt = "updates.lastAttempt"
    }

    private init() {
        #if DEBUG
        // -UpdateRepository owner/name checks another repository's releases, to try the menu bar window and Settings.
        if let repository = UserDefaults.standard.string(forKey: "UpdateRepository") {
            feed.repository = repository
            keepsState = false
            return
        }
        #endif
        latest = defaults.data(forKey: Key.latest).flatMap { try? JSONDecoder().decode(Release.self, from: $0) }
        lastChecked = defaults.object(forKey: Key.lastChecked) as? Date
        lastAttempt = defaults.object(forKey: Key.lastAttempt) as? Date
    }

    /// Starts the automatic checks; call once, at launch.
    func start() {
        guard schedule == nil else { return }
        #if DEBUG
        // Development builds check only when asked; -CheckForUpdates YES (or -UpdateRepository) checks at launch.
        guard UserDefaults.standard.bool(forKey: "CheckForUpdates") || !keepsState else { return }
        #endif
        schedule = Task {
            try? await Task.sleep(for: .seconds(5))
            await checkIfDue(after: 60 * 60)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60 * 60))
                await checkIfDue(after: 24 * 60 * 60)
            }
        }
    }

    /// Checks unless GitHub was asked less than `interval` ago.
    private func checkIfDue(after interval: TimeInterval) async {
        if let last = [lastChecked, lastAttempt].compactMap({ $0 }).max(), Date.now.timeIntervalSince(last) < interval { return }
        await check()
    }

    /// Asks GitHub for the newest release now.
    func check() async {
        guard !isChecking else { return }
        guard VersionNumber.isValid(BuildInfo.version) else {
            failure = "This build has no version number (swift run)."
            return
        }
        isChecking = true
        defer { isChecking = false }
        lastAttempt = .now
        save(lastAttempt, Key.lastAttempt)
        do {
            latest = try await feed.latestRelease()
            lastChecked = .now
            failure = nil
            save(latest.flatMap { try? JSONEncoder().encode($0) }, Key.latest)
            save(lastChecked, Key.lastChecked)
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Opens the release's disk image (the browser downloads it), or its page when it has none.
    func download(_ release: Release) {
        NSWorkspace.shared.open(release.downloadURL ?? release.pageURL)
    }

    private func save(_ value: Any?, _ key: String) {
        guard keepsState else { return }
        defaults.set(value, forKey: key)
    }
}
