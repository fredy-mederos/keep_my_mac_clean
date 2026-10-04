# KeepMyMacClean

A small menu bar app that shows how much disk space is left, how fast it's shrinking, and lets
you pick developer junk to clean: Xcode DerivedData, Gradle caches, project `build/` and
`node_modules/` folders, old simulator runtimes, old IDE versions, package manager caches, Docker
data, plus your own large files and forgotten downloads.

Cleaning is always manual: nothing is deleted until you select it and confirm.

## Build and run

```bash
./scripts/build-app.sh --install   # builds dist/KeepMyMacClean.app, copies it to ~/Applications, launches it
swift run KeepMyMacClean           # quick dev run (no notifications or login item outside a .app)
swift test                         # unit tests (use a fake home folder, never touch real files)
swift run kmmc scan                # read-only: print what the app would find
swift run kmmc discover            # read-only: show where your projects were found
swift run kmmc history             # read-only: free-space samples and the current trend
```

`build-app.sh` stamps each build: the version in `Resources/Info.plist` (bumped by hand for milestones), the
build number (commit count), the short commit hash (`-dirty` when built with uncommitted changes) and the build
date. Settings → About shows them.

On first launch the app walks your home folder for projects and remembers their parent folders
(`~/Documents/projects`, `~/AndroidStudioProjects`...). Edit them in Settings. macOS asks once for
access to Documents, Desktop and Downloads.

## How items are classified

| Kind | Meaning | Examples |
|---|---|---|
| Safe | The owning tool recreates it. Cost: a slower next build or a re-download. | DerivedData, project build folders, Gradle build cache, npm/pnpm caches, unavailable simulators |
| Review | Probably not needed, but worth a look. | iOS DeviceSupport, simulator runtimes, old Android Studio versions, Gradle dependencies, CocoaPods specs repo, older SDK platforms, unused Docker images and volumes |
| My files | Your own files. Only ever moved to the Trash, with a suggestion for each. | Installers, archives already extracted, APK/IPA builds, videos, VM disks, ML models, old downloads |

Caches are deleted permanently (moving gigabytes of caches to the Trash frees nothing); your own files
go to the Trash.

Every item says why it's listed, what cleaning costs and what happens afterwards (the ⓘ button). Review
rows show the cost inline, colored by level:

| Cost level | Meaning | Examples |
|---|---|---|
| Rebuild | Recreated locally, next build is slower | DerivedData, Gradle build cache |
| Re-download | Fetched again from the network | Simulator runtimes ("~8.8 GB from Apple"), Gradle dependencies, SDK platforms |
| Lose an option | No data lost, but a possibility is gone | Toolbox rollback backups, old IDE settings |
| Data loss | Can't be recovered (red, and called out when confirming) | Emulators, Docker volumes and stopped containers, Xcode archives (dSYMs) |

Facts come from your projects where cheap: which Gradle version each project's wrapper uses, which API levels
they compile against, which Podfiles still use the git CocoaPods specs, how many simulators use a runtime.

## Smarter suggestions (optional)

With Settings → Suggestions → "Smarter suggestions (on-device AI)" on (macOS 26+ with Apple Intelligence),
Apple's on-device Foundation Models write a one-line suggestion for each of your own files from its name, type,
folder, size and dates. Suggestions are generated when a row appears, cached in
`~/Library/Application Support/KeepMyMacClean/suggestions.json`, and fall back to the fixed text. The model
only writes text; it never changes what an item is or what cleaning does. Nothing leaves your Mac. Where a tool
has its own cleanup command, the app uses it (`xcrun simctl delete unavailable`, `xcrun simctl runtime delete`).
Every path passes `PathGuard` before deletion: it must be at least two levels inside your home folder and
never one of the well-known folders.

Project artifacts only count when the matching build file sits next to them: `build/` next to
`build.gradle(.kts)` or `pubspec.yaml`, `node_modules/` next to `package.json`, `Pods/` next to `Podfile`, and so on.

## Free space history

The app samples free space every 30 minutes while it runs and keeps 90 days in
`~/Library/Application Support/KeepMyMacClean/history.json`. The trend ("−2 GB/day · full in ~14 days")
uses the last 7 days and ignores jumps up from cleanups, so cleaning doesn't hide how fast the disk fills.
A full scan runs every 6 hours; categories that grew more than 500 MB in about a week show it.
A notification fires when free space drops below your threshold, or when the current pace fills the disk within a week.

## Layout

- `Sources/CleanerCore`: scanning, sizing, project discovery, cleaning. No UI.
  - `Scanners/`: one scanner per category. Scanners list items quickly and return probes; `ScanEngine`
    measures probes in parallel and streams results.
- `Sources/KeepMyMacClean`: SwiftUI `MenuBarExtra` app.
- `Sources/kmmc`: read-only CLI.
- `Tests/CleanerCoreTests`: Swift Testing suite.

## Roadmap

1. ✅ Menu bar free space, dev cleaners (safe + review), project discovery, low-space alert, open at login
2. ✅ One-click selection of inactive projects and DerivedData, older Android SDK platforms/sources/build tools, Docker (`docker system df` + prune)
3. ✅ Large files and downloads with suggestions (Trash only), free-space history, trend and "days until full", category growth, redesigned popover
4. ✅ Cost of cleaning on every item (reason, cost level, ⓘ details, data-loss warning), optional on-device AI suggestions, build version in Settings
5. Treemap explorer, Full Disk Access view of hidden space (Trash, Photos, device backups)
