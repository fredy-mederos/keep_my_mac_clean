import CleanerCore
import Foundation

// Read-only companion CLI: shows what KeepMyMacClean would find. It never deletes anything.

let home = FileManager.default.homeDirectoryForCurrentUser
let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "scan"

func printDisk() {
    guard let disk = try? DiskSpace.read() else { return print("Couldn't read disk space") }
    print("Free: \(ByteFormat.short(disk.available)) of \(ByteFormat.short(disk.total)) (\(Int(disk.usedFraction * 100))% used)")
}

func locations() -> [URL] {
    let settings = SettingsStore().load()
    if settings.hasDiscoveredProjects {
        return settings.projectLocations.map { URL(fileURLWithPath: $0) }
    }
    return ProjectDiscovery.discoverLocations(home: home)
}

switch command {
case "disk":
    printDisk()

case "discover":
    let start = Date()
    let found = ProjectDiscovery.discoverLocations(home: home)
    print("Project locations (\(String(format: "%.1f", Date().timeIntervalSince(start)))s):")
    for location in found {
        let projects = ProjectDiscovery.projects(inLocations: [location])
        print("  \(PathFormat.abbreviated(location))  (\(projects.count) projects)")
    }

case "scan":
    printDisk()
    let context = ScanContext(
        home: home,
        projectLocations: locations(),
        largeFileMinimumSize: SettingsStore().load().largeFileThresholdBytes
    )
    print("Project locations: \(context.projectLocations.map { PathFormat.abbreviated($0) }.joined(separator: ", "))\n")
    let start = Date()
    var firstSeen: [String: TimeInterval] = [:]
    var lastSnapshot: ScanSnapshot?
    var reportedTenSeconds = false
    for await snapshot in ScanEngine.run(context: context) {
        let elapsed = Date().timeIntervalSince(start)
        for category in snapshot.categories where firstSeen[category.id] == nil {
            firstSeen[category.id] = elapsed
        }
        if elapsed > 10, !reportedTenSeconds {
            reportedTenSeconds = true
            print("After 10s: \(snapshot.categories.flatMap(\.items).count) items shown, \(snapshot.pending) still measuring")
        }
        lastSnapshot = snapshot
    }
    print(String(format: "Scan finished in %.1fs\n", Date().timeIntervalSince(start)))
    var totals: [Safety: Int64] = [:]
    for category in lastSnapshot?.categories ?? [] {
        let shown = String(format: "first shown after %.1fs", firstSeen[category.id] ?? 0)
        print("== \(category.title): \(ByteFormat.standard(category.totalSize)) (\(category.items.count) items, \(shown))")
        for item in category.items {
            totals[item.safety, default: 0] += item.size
            let size = ByteFormat.standard(item.size).padding(toLength: 10, withPad: " ", startingAt: 0)
            let badge = switch item.safety {
            case .safe: ""
            case .review: "[review] "
            case .personal: "[to trash] "
            }
            print("   \(size) \(badge)\(item.title)\(item.detail.map { " — \($0)" } ?? "")")
            if item.safety == .review, let cost = item.cost {
                print("              ↳ \(item.costLevel?.label ?? "No cost"): \(cost)")
                if let reason = item.reason { print("                \(reason)") }
            }
        }
        print()
    }
    print("Safe: \(ByteFormat.standard(totals[.safe] ?? 0)) · Review: \(ByteFormat.standard(totals[.review] ?? 0))")

case "history":
    let history = HistoryStore().load()
    print("\(history.samples.count) free-space samples, \(history.scans.count) scan records")
    if let first = history.samples.first, let last = history.samples.last {
        print("From \(first.date.formatted()) (\(ByteFormat.short(first.available)) free) to \(last.date.formatted()) (\(ByteFormat.short(last.available)) free)")
    }
    if let trend = history.trend() {
        let days = trend.daysUntilFull.map { String(format: ", full in ~%.0f days", $0) } ?? ""
        print("Trend: \(ByteFormat.short(Int64(trend.bytesPerDay))) per day\(days)")
    } else {
        print("Trend: not enough history yet (needs 12 hours)")
    }

default:
    print("usage: kmmc [scan|disk|discover|history]")
}
