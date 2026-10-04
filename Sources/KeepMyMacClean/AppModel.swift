import AppKit
import CleanerCore
import Observation

@MainActor
@Observable
final class AppModel {
    enum CleanPhase: Equatable {
        case idle
        case confirming
        case cleaning(done: Int, total: Int, current: String)
        /// Making sure what was cleaned is really gone.
        case verifying
        case finished(freed: Int64, trashed: Int64, cleaned: Int, errors: [String])
    }

    enum SpaceStatus {
        case good, tight, low
    }

    private(set) var disk: DiskSpace?
    private(set) var categories: [CleanupCategory] = []
    private(set) var isScanning = false
    private(set) var pendingMeasurements = 0
    private(set) var scanStatus: String?
    private(set) var lastScan: Date?
    private(set) var history: SpaceHistory
    var selection: Set<String> = []
    var expanded: Set<String> = []
    /// Show only one kind of item (safe, review, your files). Nil shows everything.
    var filter: Safety?
    var phase: CleanPhase = .idle
    private(set) var runningBlockers: [Blocker] = []
    let suggestions = SmartSuggestions()
    /// The weekly summary, computed from the history.
    private(set) var digestFacts: DigestFacts?
    private(set) var digestText: (headline: String, body: String)?

    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            try? store.save(settings)
        }
    }

    private let store = SettingsStore()
    private let historyStore = HistoryStore()
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var lowSpaceAlertSent = false

    /// Scans again in the background this often, so category growth can be tracked.
    private let autoRescanInterval: TimeInterval = 6 * 3600

    init() {
        settings = store.load()
        history = historyStore.load()
        Task { await start() }
    }

    // MARK: Lifecycle

    private func start() async {
        // No Dock icon, also when started with `swift run` (the bundled app sets LSUIElement).
        NSApp.setActivationPolicy(.accessory)
        Notifier.requestAuthorization()
        refreshDisk()
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                refreshDisk()
                if let lastScan, Date().timeIntervalSince(lastScan) > autoRescanInterval, phase == .idle {
                    await rescan()
                }
            }
        }
        if !settings.hasDiscoveredProjects {
            await discoverProjects()
        }
        await rescan()
    }

    // MARK: Disk space

    var menuBarText: String {
        disk.map { ByteFormat.short($0.available) } ?? "–"
    }

    var isLowOnSpace: Bool { spaceStatus == .low }

    var spaceStatus: SpaceStatus {
        guard let disk else { return .good }
        let threshold = settings.lowSpaceThresholdBytes
        if disk.available < threshold { return .low }
        if disk.available < threshold * 2 { return .tight }
        return .good
    }

    var trend: SpaceTrend? { history.trend() }
    var recentSamples: [SpaceSample] { history.recentSamples() }

    func refreshDisk() {
        guard let latest = try? DiskSpace.read() else { return }
        disk = latest
        if history.record(SpaceSample(date: Date(), available: latest.available, total: latest.total)) {
            saveHistory()
            refreshDigest()
        }
        checkLowSpace(latest)
        checkFillingFast()
    }

    private func checkLowSpace(_ disk: DiskSpace) {
        let threshold = settings.lowSpaceThresholdBytes
        if disk.available < threshold {
            if !lowSpaceAlertSent, settings.notifyOnLowSpace {
                Notifier.post(
                    title: "Your Mac is running out of space",
                    body: "\(ByteFormat.short(disk.available)) left. Open KeepMyMacClean to see what you can clean."
                )
            }
            lowSpaceAlertSent = true
        } else if disk.available > threshold + 2_000_000_000 {
            // Re-arm only after a clear recovery so the alert doesn't flap around the threshold.
            lowSpaceAlertSent = false
        }
    }

    /// Warns at most every 3 days when the current pace fills the disk within a week.
    private func checkFillingFast() {
        guard settings.notifyOnLowSpace, let days = trend?.daysUntilFull, days < 7 else { return }
        if let last = history.lastFillingAlert, Date().timeIntervalSince(last) < 3 * 86_400 { return }
        Notifier.post(
            title: "Your disk is filling up fast",
            body: "At this pace it's full in about \(max(Int(days), 1)) days. Open KeepMyMacClean to see what's growing."
        )
        history.lastFillingAlert = Date()
        saveHistory()
    }

    private func saveHistory() {
        try? historyStore.save(history)
    }

    // MARK: Projects

    var projectLocations: [URL] {
        settings.projectLocations.map { URL(fileURLWithPath: $0) }
    }

    /// Walks the home folder for projects and remembers where they live.
    /// Keeps locations you added yourself.
    func discoverProjects() async {
        scanStatus = "Looking for your projects…"
        let home = self.home
        let found = await Task.detached(priority: .utility) {
            ProjectDiscovery.discoverLocations(home: home)
        }.value
        settings.projectLocations = ProjectDiscovery.collapse(settings.projectLocations + found.map(\.path))
        settings.hasDiscoveredProjects = true
        scanStatus = nil
    }

    func addProjectLocation(_ url: URL) {
        settings.projectLocations = ProjectDiscovery.collapse(settings.projectLocations + [url.standardizedFileURL.path])
        Task { await rescan() }
    }

    func removeProjectLocation(_ path: String) {
        settings.projectLocations.removeAll { $0 == path }
        Task { await rescan() }
    }

    // MARK: Scanning

    /// Set when a rescan is asked for while one is running, so it runs again with fresh data.
    private var rescanRequested = false

    func rescan() async {
        guard !isScanning else {
            rescanRequested = true
            return
        }
        isScanning = true
        scanStatus = "Scanning…"
        defer {
            isScanning = false
            pendingMeasurements = 0
            scanStatus = nil
        }
        let context = ScanContext(
            home: home,
            projectLocations: projectLocations,
            largeFileMinimumSize: settings.largeFileThresholdBytes
        )
        for await snapshot in ScanEngine.run(context: context) {
            categories = snapshot.categories
            pendingMeasurements = snapshot.pending
        }

        selection.formIntersection(Set(allItems.map(\.id)))
        lastScan = Date()
        history.record(scan: ScanRecord(date: Date(), categories: categories))
        saveHistory()
        refreshDisk()
        refreshDigest()
        if rescanRequested {
            rescanRequested = false
            await rescan()
        }
    }

    // MARK: Weekly summary

    /// Recomputes the summary from the history. The text is written by the app, not a model: in testing the
    /// on-device model's version was accurate but left out the most useful details (what grew, the pace).
    func refreshDigest() {
        guard !categories.isEmpty, let facts = Digest.facts(history: history, categories: categories) else {
            digestFacts = nil
            digestText = nil
            return
        }
        digestFacts = facts
        digestText = Digest.plainSummary(facts)
        sendWeeklySummaryIfDue(facts)
    }

    private func sendWeeklySummaryIfDue(_ facts: DigestFacts) {
        guard settings.weeklySummary, facts.isFullWeek, let text = digestText else { return }
        if let last = history.lastWeeklySummary, Date().timeIntervalSince(last) < 6.5 * 86_400 { return }
        Notifier.post(title: text.headline, body: text.body.isEmpty ? "Open KeepMyMacClean to see what changed." : text.body)
        history.lastWeeklySummary = Date()
        saveHistory()
    }

    /// Shows an item from the summary: clears the filter, expands its category and selects it.
    func focus(onItem id: String) {
        guard let category = categories.first(where: { $0.items.contains { $0.id == id } }) else { return }
        filter = nil
        expanded.insert(category.id)
        selection.insert(id)
    }

    /// Growth of a category over about a week, when it's big enough to mention.
    func growth(ofCategory id: String) -> CategoryGrowth? {
        guard let category = categories.first(where: { $0.id == id }),
              let growth = history.growth(of: id, currentSize: category.totalSize),
              growth.bytes >= 500_000_000
        else { return nil }
        return growth
    }

    // MARK: Selection

    var allItems: [CleanupItem] { categories.flatMap(\.items) }
    var selectedItems: [CleanupItem] { allItems.filter { selection.contains($0.id) } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    /// Categories as shown, after applying the filter.
    var visibleCategories: [CleanupCategory] {
        guard let filter else { return categories }
        return categories.compactMap { category in
            var filtered = category
            filtered.items = category.items.filter { $0.safety == filter }
            return filtered.items.isEmpty ? nil : filtered
        }
    }

    func total(_ safety: Safety) -> Int64 {
        categories.reduce(0) { $0 + $1.size(of: safety) }
    }

    func toggleFilter(_ safety: Safety) {
        filter = filter == safety ? nil : safety
    }

    func toggle(_ item: CleanupItem) {
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    func selectionState(of category: CleanupCategory) -> CheckState {
        let selected = category.items.filter { selection.contains($0.id) }.count
        if selected == 0 { return .off }
        return selected == category.items.count ? .on : .mixed
    }

    func toggle(_ category: CleanupCategory) {
        let ids = category.items.map(\.id)
        if selectionState(of: category) == .on {
            selection.subtract(ids)
        } else {
            selection.formUnion(ids)
        }
    }

    var inactiveCutoff: Date {
        Calendar.current.date(byAdding: .month, value: -settings.inactiveAfterMonths, to: Date()) ?? Date()
    }

    func inactiveItems(in category: CleanupCategory) -> [CleanupItem] {
        category.inactiveItems(notUsedSince: inactiveCutoff)
    }

    func selectInactive(in category: CleanupCategory) {
        selection.formUnion(inactiveItems(in: category).map(\.id))
    }

    func selectAllSafe() {
        selection.formUnion(allItems.filter { $0.safety == .safe }.map(\.id))
    }

    func toggleExpanded(_ category: CleanupCategory) {
        if expanded.contains(category.id) { expanded.remove(category.id) } else { expanded.insert(category.id) }
    }

    // MARK: Cleaning

    func requestClean() {
        guard !selection.isEmpty else { return }
        runningBlockers = BlockerCheck.running(selectedItems.flatMap(\.blockers))
        phase = .confirming
    }

    func cancelClean() {
        phase = .idle
    }

    func clean() async {
        let items = selectedItems
        guard !items.isEmpty else { return }
        let cleaner = Cleaner(home: home)
        var errors: [String] = []
        var cleanedIDs = Set<String>()
        var freed: Int64 = 0
        var trashed: Int64 = 0

        for (index, item) in items.enumerated() {
            phase = .cleaning(done: index, total: items.count, current: item.title)
            let outcome = await Task.detached(priority: .userInitiated) { cleaner.clean(item) }.value
            if let error = outcome.error {
                errors.append("\(item.title): \(error)")
            } else {
                cleanedIDs.insert(item.id)
            }
        }

        // A command can exit successfully without removing anything, so check before claiming space back.
        phase = .verifying
        let stillThere = await itemsStillPresent(items.filter { cleanedIDs.contains($0.id) })
        for item in stillThere {
            cleanedIDs.remove(item.id)
            errors.append("\(item.title): still there after cleaning")
        }
        for item in items where cleanedIDs.contains(item.id) {
            if item.action.movesToTrash { trashed += item.size } else { freed += item.size }
        }

        for index in categories.indices {
            categories[index].items.removeAll { cleanedIDs.contains($0.id) }
        }
        categories.removeAll { $0.items.isEmpty }
        selection.subtract(cleanedIDs)
        refreshDisk()
        phase = .finished(freed: freed, trashed: trashed, cleaned: cleanedIDs.count, errors: errors)

        // Then bring the whole list in line with the disk.
        Task { await rescan() }
    }

    /// Cleaned items that are in fact still there: files or folders left on disk, or, for commands,
    /// items their scanner still finds at about the same size.
    private func itemsStillPresent(_ items: [CleanupItem]) async -> [CleanupItem] {
        var stillThere: [CleanupItem] = []
        var commandItems: [CleanupItem] = []
        for item in items {
            switch item.action {
            case .removePaths(let urls), .moveToTrash(let urls):
                if urls.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) { stillThere.append(item) }
            case .command:
                commandItems.append(item)
            }
        }
        guard !commandItems.isEmpty else { return stillThere }

        let categoryIDs = Set(commandItems.compactMap { item in categories.first { $0.items.contains { $0.id == item.id } }?.id })
        let scanners = ScanEngine.scanners.filter { categoryIDs.contains($0.categoryID) }
        let context = ScanContext(home: home, projectLocations: projectLocations, largeFileMinimumSize: settings.largeFileThresholdBytes)
        var fresh: [CleanupItem] = []
        for await snapshot in ScanEngine.run(scanners, context: context) {
            fresh = snapshot.categories.flatMap(\.items)
        }
        for item in commandItems {
            if let again = fresh.first(where: { $0.id == item.id }), again.size >= item.size / 2 {
                stillThere.append(item)
            }
        }
        return stillThere
    }

    // MARK: Suggestions

    /// The suggestion shown for one of your files: the on-device model's when enabled and ready,
    /// otherwise the fixed one.
    func suggestion(for item: CleanupItem) -> (text: String, isGenerated: Bool)? {
        if settings.smartSuggestions, let generated = suggestions.text(for: item) {
            return (generated, true)
        }
        return item.reason.map { ($0, false) }
    }

    /// What a project is: the on-device model's one-liner when enabled and ready, otherwise the plain line.
    func projectBlurb(for item: CleanupItem) -> (text: String, isGenerated: Bool)? {
        guard let project = item.project else { return nil }
        if settings.smartSuggestions, project.wantsModelSummary, let generated = suggestions.text(for: item) {
            return (generated, true)
        }
        return project.plainBlurb.map { ($0, false) }
    }

    func requestSuggestion(for item: CleanupItem) {
        guard settings.smartSuggestions else { return }
        suggestions.request(item)
    }

    // MARK: Misc

    func reveal(_ item: CleanupItem) {
        guard let url = item.revealURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

enum CheckState {
    case on, off, mixed
}
