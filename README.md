# KeepMyMacClean

A small menu bar app that shows how much disk space is left and lets you pick developer
junk to clean: Xcode DerivedData, Gradle caches, project `build/` and `node_modules/`
folders, old simulator runtimes, old IDE versions, package manager caches and more.

Cleaning is always manual: nothing is deleted until you select it and confirm.

## Build and run

```bash
./scripts/build-app.sh --install   # builds dist/KeepMyMacClean.app, copies it to ~/Applications, launches it
swift run KeepMyMacClean           # quick dev run (no notifications or login item outside a .app)
swift test                         # unit tests (use a fake home folder, never touch real files)
swift run kmmc scan                # read-only: print what the app would find
swift run kmmc discover            # read-only: show where your projects were found
```

On first launch the app walks your home folder for projects and remembers their parent folders
(`~/Documents/projects`, `~/AndroidStudioProjects`...). Edit them in Settings. macOS asks once for
access to Documents, Desktop and Downloads.

## How items are classified

| Kind | Meaning | Examples |
|---|---|---|
| Safe | The owning tool recreates it. Cost: a slower next build or a re-download. | DerivedData, project build folders, Gradle build cache, npm/pnpm caches, unavailable simulators |
| Review | Probably not needed, but worth a look. | iOS DeviceSupport, simulator runtimes, old Android Studio versions, Gradle dependencies, CocoaPods specs repo, older SDK platforms, unused Docker images and volumes |

Folders are deleted permanently (moving gigabytes of caches to the Trash frees nothing). Where a tool
has its own cleanup command, the app uses it (`xcrun simctl delete unavailable`, `xcrun simctl runtime delete`).
Every path passes `PathGuard` before deletion: it must be at least two levels inside your home folder and
never one of the well-known folders.

Project artifacts only count when the matching build file sits next to them: `build/` next to
`build.gradle(.kts)` or `pubspec.yaml`, `node_modules/` next to `package.json`, `Pods/` next to `Podfile`, and so on.

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
3. Big files, installers and Downloads finder; free-space history and "days until full"
4. Treemap explorer, Full Disk Access view of hidden space (Trash, Photos, device backups)
