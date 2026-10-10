---
name: release-vibe-clean
description: "Publish a Vibe Clean release end-to-end: check the repository, resolve and confirm the version, build a signed and notarized VibeClean.dmg, tag it and publish a GitHub release with the DMG. Use when asked to release or publish Vibe Clean (formerly KeepMyMacClean), cut a new version, or upload a DMG to GitHub. Not for `scripts/build-app.sh --install`, which only installs a local build."
---

# Release Vibe Clean

## Overview

Run these steps in order. Installed copies of Vibe Clean ask GitHub for the newest release
(`Sources/KeepMyMacClean/AppUpdater.swift`) at launch and once a day, so a published release reaches them within a
day. They compare the release tag (`vX.Y.Z`) with their own version and download the attached `VibeClean.dmg` (copies from
before the rename, 1.1.0, ask for the old repository name, which GitHub redirects, and take the only disk image).

## Workflow

1. Check pending changes.
- Run `git status` and `git diff`.
- If there are changes, run `swift test`, then commit them with a message that describes them (the repository's
  own identity, `Fredy Mederos <fmfredd@gmail.com>`) and push.
- If there are none, continue.

2. Resolve the version.
- `scripts/version.sh` prints the app's version (`CFBundleShortVersionString` in `Resources/Info.plist`).
- `git tag --list 'v*' --sort=-v:refname | head -1` is the latest release tag.
- No tag yet, or the app's version is newer than the latest tag: use the app's version.
- The app's version matches the latest tag: bump the minor version (`X.Y.Z` -> `X.(Y+1).0`).

3. Confirm the version with the user.
- If they want a different one, use theirs.

4. Set and commit the version when it changed.
- Run `scripts/version.sh X.Y.Z`, then commit `Resources/Info.plist` as `Bump version to X.Y.Z`.
- Don't push yet. The build stamps the commit it's made from, so the version is committed first.

5. Build, sign, notarize, staple.
- Run:
```bash
APP_SIGN_IDENTITY="Developer ID Application: Fredy Mederos (R72WZKM2MR)" \
  NOTARY_KEYCHAIN_PROFILE="wispr-notary" scripts/release.sh
```
- If it fails, stop and report the error. The version commit stays local and unpushed.

6. Push the commit, then create and push the tag.
- Run `git push`.
- Run `git tag vX.Y.Z`.
- Run `git push origin vX.Y.Z`.

7. Create the GitHub release.
- Run:
```bash
gh release create vX.Y.Z dist/VibeClean.dmg --repo fredy-mederos/vibe_clean \
  --title "Vibe Clean vX.Y.Z" --notes-file <(scripts/release-notes.sh vX.Y.Z)
```
- Share the release URL at completion.

8. Check that installed copies will see it.
- `curl -s https://api.github.com/repos/fredy-mederos/vibe_clean/releases/latest | grep -E '"(tag_name|browser_download_url)"'`
  shows `vX.Y.Z` and `VibeClean.dmg`.

## Guardrails

- Do not tag or publish if the tests, the build, signing or notarization failed.
- Never publish a build made from uncommitted changes: `scripts/create_dmg.sh` refuses them unless `ALLOW_DIRTY=1`,
  which is only for test builds.
- Stop and ask before using a version different from the resolved one.
