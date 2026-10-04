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
        case finished(freed: Int64, cleaned: Int, errors: [String])
    }

    private(set) var disk: DiskSpace?
    private(set) var categories: [CleanupCategory] = []
    private(set) var isScanning = false
    private(set) var scanStatus: String?
    private(set) var lastScan: Date?
    var selection: Set<String> = []
    var expanded: Set<String> = []
    var phase: CleanPhase = .idle
    private(set) var runningBlockers: [Blocker] = []

    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            try? store.save(settings)
        }
    }

    private let store = SettingsStore()
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var lowSpaceAlertSent = false

    init() {
        settings = store.load()
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

    var isLowOnSpace: Bool {
        guard let disk else { return false }
        return disk.available < settings.lowSpaceThresholdBytes
    }

    func refreshDisk() {
        guard let latest = try? DiskSpace.read() else { return }
        disk = latest
        checkLowSpace(latest)
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

    func rescan() async {
        guard !isScanning else { return }
        isScanning = true
        scanStatus = "Scanning…"
        defer {
            isScanning = false
            scanStatus = nil
        }
        let context = ScanContext(home: home, projectLocations: projectLocations)
        let order = ScanEngine.scanners.map(\.categoryID)
        var results: [String: CleanupCategory] = [:]

        await withTaskGroup(of: CleanupCategory.self) { group in
            for scanner in ScanEngine.scanners {
                group.addTask(priority: .utility) {
                    ScanEngine.scan(scanner, context: context)
                }
            }
            for await category in group {
                results[category.id] = category
                categories = order.compactMap { results[$0] }.filter { !$0.items.isEmpty }
            }
        }

        let ids = Set(allItems.map(\.id))
        selection.formIntersection(ids)
        lastScan = Date()
        refreshDisk()
    }

    // MARK: Selection

    var allItems: [CleanupItem] { categories.flatMap(\.items) }
    var selectedItems: [CleanupItem] { allItems.filter { selection.contains($0.id) } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    func total(_ safety: Safety) -> Int64 {
        categories.reduce(0) { $0 + $1.size(of: safety) }
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

        for (index, item) in items.enumerated() {
            phase = .cleaning(done: index, total: items.count, current: item.title)
            let outcome = await Task.detached(priority: .userInitiated) { cleaner.clean(item) }.value
            if let error = outcome.error {
                errors.append("\(item.title): \(error)")
            } else {
                cleanedIDs.insert(item.id)
                freed += item.size
            }
        }

        for index in categories.indices {
            categories[index].items.removeAll { cleanedIDs.contains($0.id) }
        }
        categories.removeAll { $0.items.isEmpty }
        selection.subtract(cleanedIDs)
        refreshDisk()
        phase = .finished(freed: freed, cleaned: cleanedIDs.count, errors: errors)
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
