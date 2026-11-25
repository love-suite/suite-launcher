# Launcher: project brief

Launcher (`local.suite.launcher`, `LSUIElement`) replaces Launchpad, which macOS 27 no longer has: a
full-screen grid of the apps (`/Applications`, `~/Applications`, `/System/Applications`), with a search
field; choosing an app opens it, Esc or a click outside closes the grid (both settings). Bar's Launcher tile
(turned on in Settings › Bar) opens it through `LauncherApp.open()` and `LauncherMessage` (`suite-core`).

The app is on `feat/launcher/core` (written in the old monorepo on 2026-11-21, moved here with its history
on 2026-11-22), not merged into `main` yet: the user hasn't tried it.

## Work to do

- A Launcher tab in Suite Settings (dismiss on Esc, on a click outside).
- An icon of its own for Bar's tile (today `square.grid.3x3.fill`).
- Folders of apps (recursive in /Applications), the order of the apps kept, groups as Launchpad's, the
  blurred background (`NSVisualEffectView`).

## Building and running

- `swift build` and `swift test` for development.
- `scripts/make-app.sh` builds `build/Launcher.app` (release), signs it with the "Suite Local Signing"
  certificate from the login keychain, so macOS permissions survive rebuilds (ad-hoc signing, the
  fallback, re-asks every build), and installs it as `~/Applications/Launcher.app`, the only copy Launch
  Services knows. It records the branch and commit in the Info.plist (`SuiteBuildBranch`,
  `SuiteBuildCommit`) and refuses to replace an installed copy built from another branch, or from an unknown
  one, unless `--force`: another session may be testing it. `INSTALL_DIR=` builds without installing. A
  running copy is relaunched from the new one.
- Never ask the user to open `build/Launcher.app` from a worktree.
- UI can't be checked by unit tests and screenshots of the user's screen are not available: check UI by
  rendering views offscreen (`cacheDisplay`) from a scratch package that compiles the sources.
- Releases: change `VERSION` (only `Z` is this repository's own), commit, push, then `scripts/publish.sh`
  pushes the tag; `.github/workflows/release.yml` builds, signs the app with "Suite Release Signing",
  signs `update.json` with the update key (both from the repository's `release` environment secrets),
  publishes the release and updates the cask in `love-suite/homebrew-tap`. The feed is
  `https://github.com/love-suite/suite-launcher/releases/latest/download/update.json`
  (the GitHub repository it is built from). A change of `AA.Y` comes from the suite repository through
  `.github/workflows/sync-version.yml`. Until `Support/release-certificate.cer` and
  `Support/update-public-key.txt` exist, nothing can be released.

## The suite

This repository is part of Love Suite, one repository per app under `github.com/love-suite`:
`suite-core` (the shared library), `suite-files` (the file layer of the apps handling files),
`suite-guard`, `suite-desktop` (the desktop), `suite-explorer`, `suite-bar` (the Dock), `suite-viewer`,
`suite-clipboard`, `suite-settings` (the settings), `suite-awake` (keeping the Mac awake), `suite-launcher`, `suite-bindings`,
`suite-ai-organizer`; `homebrew-tap` (the tap `love-suite/tap`, one cask per app) and `suite` (the
front page, the suite's version, the scripts that act on every repository). Locally they sit side by side
in `~/GitHub/paul-amour/suite/`.

## Conventions (the same in every repository of the suite)

- The user writes in French and expects answers in French; everything in the code stays in English: code,
  comments, tests, docs, commit messages. Do not add co-author trailers.
- No "…" in menu items, buttons or messages: the user wants none, anywhere.
- Behaviour follows Windows unless Apple's design is asked for.
- Swift Package Manager, `swift-tools-version:5.9`, macOS 13+. Tests use Swift Testing (`import Testing`).
- Toolchain: swiftly, Swift 6.4.2 (`.swift-version`, git-ignored). If `swift test` complains about a
  missing toolchain: `swiftly use 6.4.2`.
- AppKit for windows that need fine control; SwiftUI is allowed for small panels (settings, pickers).
- No private APIs and no system modifications (SIP stays on).
- Git: one worktree per feature under `.worktrees/` (git-ignored), one branch per change
  (`feat/<feature>`, `fix/<area>/<what>`), merged into `main` one by one; `main` stays stable.
- Versions are `AA.Y`, then `AA.Y.Z` for a fix (`VERSION`, tag `vVERSION`: 27.1, then 27.1.1; SwiftPM reads
  `v27.1` as 27.1.0): `AA` is the latest macOS in production (27), `AA.Y` is the same in every repository of
  the suite so the apps work together, `Z` is this repository's own. A change of `AA.Y` is made in `suite`
  and reaches every repository. While a version is being prepared, `VERSION` doesn't move (27.1 now):
  development builds are `VERSION-dev.N`, N the commits since `VERSION` was set, merges aside, from 1 (`make-app.sh`),
  and a change another repository needs gets a development tag, `vVERSION-dev.N`, which releases nothing.
  Dependencies on other repositories of the suite (`suite-core`, `suite-files`, `suite-guard`, settings
  libraries) use
  `.upToNextMinor(from: "27.1.0-dev.1")` (the latest development tag, then the release);
  `Package.resolved` is committed. Tags are never moved once pushed. The build number (`CFBundleVersion`,
  which the updater compares) stays the number of commits.
- Changing two repositories at once: `swift package edit <Package> --path ../<repository>` points at the
  neighbour's working copy until its tag exists, `swift package unedit` goes back. Never committed.
- What two apps need lives in `suite-core` (file code in `suite-files`); an app's own code never goes into another app's repository, and
  an app exposes only its settings, as `<App>Settings`, for Suite Settings.
- Do not run commands that delete user data. Trash instead of delete.
- No code converting saved settings at launch. Before the first release nothing needs converting (the
  developer's own settings don't count): rename freely. Between released versions, a change to saved
  settings is a `SettingsMigration` (suite-core) for the version that brought it, given to the app's
  `SuiteUpdater`, which runs it once after the update.
