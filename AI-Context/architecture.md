# AppX Manager — Onboarding & Architecture Reference

Derived from reading the actual source in this repository (every `.swift` file under
`AppX Manager/AppX Manager/`, the Xcode project's `project.pbxproj` build settings, the test
targets, and `.gitignore`) — nothing here comes from external documentation. The original
product build spec (pre-implementation) is preserved for historical reference at
`../../design/AppX_Manager_BUILD_SPEC.md`; where it disagreed with the current source, the
source won and this doc reflects the source.

Analysis date: 2026-08-17. Re-verify specifics before relying on them for a release or
compliance decision — deployment targets, dependency versions, and scheme/config names drift.

## About this doc set

- **Scope**: the entire AppX Manager macOS app (all 3 Xcode targets: `AppX Manager`,
  `AppX ManagerTests`, `AppX ManagerUITests`). Does not cover the outer `AppsUpdater/` workspace
  wrapper folder itself (its `design/` reference files and workspace file) beyond what's noted
  in [Legacy Notes & Caveats](#legacy-notes--caveats).
- **Method**: direct source reading (every source file read in full), plus the project's build
  settings (`project.pbxproj`) grepped for concurrency/sandbox/deployment keys. Historical bug
  fixes referenced below were verified live (real builds, real debug-log evidence) during prior
  sessions on this exact codebase, not inferred.
- **Closed-source / internal dependencies**: none. Zero third-party dependencies of any kind —
  the entire app is Foundation/SwiftUI/AppKit stdlib plus command-line tools it shells out to
  (`brew`, `npm`, `pip3`/`python3`, `gem`, `mas`), which are treated as black-box CLIs whose
  output shapes are parsed defensively (see [Tech Stack](#tech-stack)).

## Quick facts

| | |
|---|---|
| App | AppX Manager — native macOS dashboard to see and update everything installed on a Mac (App Store apps, direct-download apps, Homebrew formulae/casks, npm/pip/gem global packages) from one place |
| Primary language(s) | Swift only (no Objective-C bridging headers) |
| UI framework | SwiftUI exclusively — no UIKit; AppKit used only for a handful of `NSWorkspace` interop calls |
| Concurrency model | Swift Concurrency (async/await) throughout. One `@MainActor @Observable` class (`ScanEngine`) owns all UI-facing state. One `actor` (`CaskFallbackMatcher`) for a thread-safe shared cache. `Task.detached` used deliberately (3 places) as a cancellation-immunity escape hatch. `withTaskGroup` used twice, for two different reasons (see [Code Flow](#code-flow)). Blocking `Process` calls run on a dedicated `DispatchQueue`, never `Task.detached` (pool-starvation risk) |
| Deployment target | macOS 26.5+ (Xcode 26.6 toolchain; `SWIFT_VERSION` language mode 5.0 but `SWIFT_APPROACHABLE_CONCURRENCY = YES`) |
| Platforms / device families | macOS only, one universal app target |
| Persistence | None beyond a single `@AppStorage("hasCompletedOnboarding")` Bool and an append-only debug log file on disk. No database, no SwiftData/CoreData (removed from the default Xcode template during initial build) |
| Real-time / networking transport | `URLSession` for 3 read-only HTTPS GETs (Homebrew cask catalog JSON, per-app Sparkle appcast XML, iTunes Search API JSON) + Foundation `Process` for shelling out to package-manager CLIs |
| Auth | None — single-user local Mac utility, no accounts, no login |
| Automated tests | Minimal. Swift Testing framework, 4 hermetic unit tests (`AppX_ManagerTests.swift`) covering only `GemScanner` text parsing and `HomebrewScanner`'s `OutdatedResponse` JSON decoding. The UI test target (`AppX ManagerUITests`) contains only Xcode's default unfilled stub tests — no real UI assertions exist |

## Table of contents

1. [Architecture](#architecture) — layers, targets, design patterns, organization
2. [Code Flow](#code-flow) — startup, scan lifecycle, update lifecycle, batch lifecycle
3. [Data Persistence](#data-persistence) — what little persists, and where
4. [Tech Stack](#tech-stack) — languages, frameworks, concurrency idioms, build tooling
5. [Platform & Deployment Support](#platform--deployment-support) — targets, signing status
6. [Features](#features) — per-module feature catalog
7. [Security](#security) — sandbox status, shell-out safety, network calls
8. [Privacy](#privacy) — what's read, what leaves the Mac
9. [Legacy Notes & Caveats](#legacy-notes--caveats) — known gaps, copy that's gone slightly stale, hard-won gotchas

## Building & running

```sh
cd "AppX Manager"
xcodebuild -project "AppX Manager.xcodeproj" -scheme "AppX Manager" -configuration Debug \
  -derivedDataPath "./.build" build
```

`-derivedDataPath "./.build"` is not optional in this environment — the default
`~/Library/Developer/Xcode/DerivedData` path is unreliable under some sandboxed terminal
sessions (see [Legacy Notes & Caveats](#legacy-notes--caveats)). To preview the dashboard
without clicking through onboarding manually:

```sh
defaults write com.Hrithik.AppX-Manager hasCompletedOnboarding -bool true
```

Unit tests only (skips the slower UI test target):

```sh
xcodebuild -project "AppX Manager.xcodeproj" -scheme "AppX Manager" -configuration Debug \
  -derivedDataPath "./.build" -only-testing:"AppX ManagerTests" test
```

### Targets / modules at a glance

| Target | Type | Purpose |
|---|---|---|
| `AppX Manager` | macOS app | The real app — everything under [Architecture](#architecture) below |
| `AppX ManagerTests` | Swift Testing bundle | 4 hermetic parsing/decoding tests, `@testable import AppX_Manager` |
| `AppX ManagerUITests` | XCTest UI bundle | Xcode default stub only — no real assertions |

---

## Architecture

### Overview

A single-target native SwiftUI macOS app with **no dependency-injection framework, no
ViewModel layer, and no database** — deliberately simple for its scope. One `@MainActor
@Observable` class, `ScanEngine`, is the sole owner of all mutable app state (scanned items,
scan progress, per-item/batch update state) and is passed by reference into every view that
needs it. Views read its `@Observable` properties directly and call its methods directly —
there is no separate `DashboardViewModel`/`ScanningViewModel` indirection layer.

```mermaid
flowchart TD
    RootView["RootView (screen state machine)"] -->|owns + drives| ScanEngine
    ScanEngine -->|sequential, one step at a time| MasScanner
    ScanEngine --> HomebrewScanner
    ScanEngine --> NpmScanner
    ScanEngine --> PipScanner
    ScanEngine --> GemScanner
    ScanEngine -->|last: needs the above results' bundle IDs/paths to exclude| SparkleScanner
    SparkleScanner -->|per app, concurrent TaskGroup| CaskFallbackMatcher
    SparkleScanner --> AppStoreLookup
    ScanEngine -->|dispatches by Provider| Updaters["HomebrewUpdater / NpmUpdater / PipUpdater / GemUpdater / MasUpdater"]
    DashboardView -->|reads state, calls methods| ScanEngine
    ScanningView -->|reads scan progress| ScanEngine
    OnboardingView -->|@AppStorage flag| RootView
```

### Targets & code sharing

One app target; no shared framework/package split. The 2 test targets depend on the app target
via `@testable import AppX_Manager` (note: module name is `AppX_Manager` with an underscore —
the space in the display name "AppX Manager" isn't valid in a Swift module name).

### Design patterns in use

| Pattern | Where | Notes |
|---|---|---|
| Single shared `@Observable` state owner (no ViewModel layer) | `Engines/ScanEngine.swift` | Views take `scanEngine: ScanEngine` directly (e.g. `DashboardView(scanEngine:onRescan:)`) and both read its state and call its methods — there is no `DashboardViewModel` |
| Adapter | `private struct ...UpdaterAdapter` at the bottom of `Engines/ScanEngine.swift` | Each `Updaters/*.swift` file is a plain `enum` with a static `update(_:)` — the adapters wrap each into the common `ItemUpdating` protocol so `ScanEngine.updater(for:)` can dispatch by `Provider` through one interface. **Note the placement**: these adapters live inside `ScanEngine.swift`, not in `Updaters/` — a minor, deliberate deviation from one-type-per-file |
| Actor-isolated singleton cache | `Engines/CaskFallbackMatcher.swift` (`CaskFallbackMatcher.shared`) | The *only* actor in the codebase — everything else is a stateless `enum` with `static func`s, or the one `@MainActor` class. Converted from a plain `enum` with an unsynchronized `static var` cache after concurrent scanning exposed a real data race (see [Legacy Notes](#legacy-notes--caveats)) |
| Cancellation-immune detached fetch | `CaskFallbackMatcher.catalog()`, `SparkleScanner.latestVersion(fromAppcast:)`, `AppStoreLookup.fetchHomepageURL` | All 3 network fetches reachable from the scan's `.task(id:)` chain are wrapped in `Task.detached { ... }.value` — a detached task has no parent/child relationship to its caller, so caller-side cancellation (which was silently killing these fetches) can't reach it. This is a recurring, deliberate pattern here — not incidental |
| Bounded-concurrency `TaskGroup` | `ScanEngine.runBatch(_:)` (cap 3), `SparkleScanner.scan()` (uncapped, one task per installed app) | Used for two different reasons: `runBatch` caps concurrency to avoid `brew`/`npm`/`pip` lock contention during real installs; `SparkleScanner.scan()` parallelizes read-only per-app classification (no such contention risk) with no cap |
| In-flight `Task` de-duplication | `ScanEngine.scan()` (`inFlightScan: Task<Void, Never>?`) | Concurrent callers await the *same* real scan instead of either double-scanning or (a prior bug) returning early with stale/empty state — see [Legacy Notes](#legacy-notes--caveats) |

### Module / folder organization

By architectural layer, not by feature — and within `Engines/`/`Updaters/`, by **source**
(one file per package manager / App Store / direct-download):

```
AppX Manager/AppX Manager/
├── App/            AppX_ManagerApp.swift (entry point), RootView.swift (screen state machine)
├── Models/         InstalledItem, Provider, Source, UpdateStatus, VersionEntry — all Sendable, Hashable
├── Engines/        One scanner enum per source + ScanEngine (the orchestrator) + 2 matchers/lookups
├── Updaters/        One enum per source with a static update(_:) async throws, + UpdaterError
├── UI/
│   ├── Onboarding/  OnboardingView (3-step flow)
│   ├── Scanning/    ScanningView (progress screen)
│   └── Dashboard/   DashboardView, SidebarView, AppRowView, DetailPanelView, BatchProgressBar
├── Support/         ShellRunner (Process wrapper), DebugLog, DiskUsage, Theme (design tokens)
└── Assets.xcassets/ App icon + accent color
```

No naming-era split — this is a young, single-pass codebase (no legacy vs. modern convention
divide to be aware of).

---

## Code Flow

### Startup / entry sequence

`AppX_ManagerApp` (the `@main` entry point) opens a single `WindowGroup` hosting `RootView`,
sized from `Theme.Layout.defaultWindowSize` (1360×860). `RootView` is a 3-state screen switcher
(`enum AppScreen { onboarding, scanning, dashboard }`) gated by `@AppStorage("hasCompletedOnboarding")`:

- First launch ever → `OnboardingView` (3 steps: welcome, Full Disk Access request, "you approve
  every update" explanation) → on completion, sets the `@AppStorage` flag and moves to `.scanning`.
- Every subsequent launch → `.onAppear` checks `hasCompletedOnboarding && scanEngine.lastScanned
  == nil` and jumps straight to `.scanning`.
- `.task(id: screen)` fires the actual scan: `guard screen == .scanning else { return }; await
  scanEngine.scan(); screen = .dashboard`.

### Auth

Not applicable — no accounts, no login, single local Mac user.

### Key runtime lifecycle #1 — Scan

`ScanEngine.scan()` is the public entry point; it de-duplicates concurrent callers (see
[Design patterns](#design-patterns-in-use)) and delegates to `performScan()`, which runs 5
package-manager scanners **sequentially** (so `ScanningView` can show one active step at a
time), then runs direct-download detection **last** (it needs the earlier results to know which
`/Applications/*.app` bundles are already accounted for by Homebrew/App Store):

```mermaid
sequenceDiagram
    participant RV as RootView
    participant SE as ScanEngine
    participant Scanners as Mas/Homebrew/Npm/Pip/Gem Scanners
    participant Sparkle as SparkleScanner
    participant Cask as CaskFallbackMatcher (actor)
    participant Lookup as AppStoreLookup

    RV->>SE: scan()
    SE->>SE: performScan() [currentStep updates per source]
    loop sequential, one at a time
        SE->>Scanners: scan()
    end
    SE->>Sparkle: scan(excludingBundleIds:, excludingPaths:)
    Note over Sparkle: withTaskGroup — one task per installed app
    par per app, concurrent
        Sparkle->>Sparkle: check Info.plist SUFeedURL, fetch appcast
        Sparkle->>Cask: match(appName:) [shared actor, single catalog fetch]
        Sparkle->>Lookup: homepageURL(appName:bundleId:) [if still unmatched]
    end
    Sparkle-->>SE: [InstalledItem]
    SE->>SE: items = merged list; lastScanned = Date()
    SE-->>RV: (awaited) — RootView sets screen = .dashboard
```

Per-app classification order inside `SparkleScanner.makeItem(for:)`: Sparkle appcast check →
Homebrew cask fallback match → (only if still unmatched) bundle-ID-verified iTunes Search
homepage lookup. The 3rd step only sets `homepageURL` for the "Visit site" UI — it never
provides a version/update path.

### Key runtime lifecycle #2 — Single-item update

`ScanEngine.performUpdate(_:)`: marks the item `.updating` (tracked in `updatingIDs`), dispatches
via `updater(for: item.provider)` to the matching adapter, and on success sets `.upToDate` and
bumps `installedVersion` to `latestVersion` — **except** `.sparkle` items, whose "update" just
opens the app (`NSWorkspace.shared.open`) since Sparkle-based apps run their own in-app updater;
opening the app doesn't confirm a real update happened, so status is deliberately left at
`.updateAvailable` rather than claiming false success. On failure, sets `.failed` and tracks the
id in `failedIDs` for the row's Retry button. Every step is logged via `DebugLog`.

### Key runtime lifecycle #3 — Batch update (Update All / Update Selected)

`runBatch(_:)` uses `withTaskGroup` with a concurrency cap of 3 (`updateConcurrencyLimit`),
refilling the group as each task finishes, updating `batchDone`/`batchTotal` for
`BatchProgressBar`. `.sparkle` and `.caskFallback` providers are excluded from batch eligibility
(`isBatchUpdatable`) — a batch run shouldn't silently open apps or adopt Homebrew casks without
explicit per-item consent.

### Key runtime lifecycle #4 — Cask adoption

`adoptIntoHomebrew(_:)` — an explicit, user-triggered action (never automatic) for
`.caskFallback` items: runs `brew install --cask <token> --force`, then flips the item's
`provider`/`source` to `.homebrewCask`/`.homebrew` in place so future updates route through
Homebrew instead of whatever installed it originally.

### Teardown / shutdown

None — no logout, no cleanup step. A simple local utility app; quitting just quits.

---

## Data Persistence

| Mechanism | What it holds | Where |
|---|---|---|
| `@AppStorage("hasCompletedOnboarding")` | A single `Bool` in `UserDefaults` | Standard app UserDefaults domain (`com.Hrithik.AppX-Manager`) |
| `DebugLog` append-only file | Every `ShellRunner` command (name/exit-code/duration/stderr-on-failure) + update/adopt lifecycle events | `~/Library/Application Support/AppX Manager/debug.log` |
| `CaskFallbackMatcher`'s in-memory cache | The ~19MB `formulae.brew.sh/api/cask.json` catalog, fetched once per app launch | In-memory only (actor property) — never written to disk, re-fetched on next launch |

No database, no SwiftData/CoreData, no migrations. This was a deliberate choice — the SwiftData
default-template scaffold was removed during initial build since the app only ever displays a
live scan result, nothing that needs to survive being recomputed.

---

## Tech Stack

### Languages

Swift only.

### UI

SwiftUI exclusively for all views. AppKit is used only for interop: `NSWorkspace.shared.open`
(opening Sparkle apps / homepage URLs / System Settings deep links), `.selectFile`/
`.activateFileViewerSelecting` (Reveal in Finder), `FileManager.trashItem` (Uninstall).

### Concurrency model

Swift Concurrency (async/await) throughout, no Combine, no completion-handler APIs written by
hand (only `Process`'s pipe-based I/O is bridged via `withCheckedThrowingContinuation`). Match
these idioms for new code:
- `@MainActor @Observable` for any new UI-facing state owner (matches `ScanEngine`) — do not
  introduce `ObservableObject`/`@Published` (Combine), the codebase uses the Observation
  framework exclusively.
- A plain stateless `enum` with `static func`s for anything that doesn't need to hold state
  (matches every `*Scanner`/`*Updater`).
- An `actor` (not a `static var` on an `enum`) for any new shared **mutable** cache reachable
  from concurrent callers — `CaskFallbackMatcher` is the cautionary example: an unsynchronized
  `static var` cache there caused a real data race once its callers became concurrent.
- `Task.detached` specifically (and only) for a network/slow `await` that must survive
  cancellation of its calling `.task(id:)` chain — don't reach for it as a general-purpose
  "run in background" tool elsewhere; it bypasses structured concurrency's cancellation and
  priority propagation, which is usually undesirable.
- Blocking calls (`Process.waitUntilExit()`) go on a dedicated concurrent `DispatchQueue`
  (`ShellRunner.ioQueue`), bridged via `withCheckedThrowingContinuation` — never
  `Task.detached`, since detached tasks still share Swift's cooperative thread pool and a
  blocking wait there risks starving it under concurrent batch updates.

### Dependency management

None. Zero Swift Package dependencies (confirmed via `project.pbxproj` — no
`packageReferences`). The entire app is Foundation + SwiftUI + AppKit stdlib, plus the
external CLIs it shells out to (`brew`, `npm`, `pip3`/`python3 -m pip`, `gem`, `mas`) and 3
public HTTPS APIs (`formulae.brew.sh`, per-app Sparkle appcast URLs, `itunes.apple.com`).

### Build tooling

Xcode / `xcodebuild` only. `project.pbxproj` `objectVersion = 77` — a modern project format
using `PBXFileSystemSynchronizedRootGroup` for all 3 targets, meaning files added/moved/deleted
on disk under a target's folder are automatically picked up; **no manual `project.pbxproj`
group/file-reference edits are needed for source files** — only build-*setting* changes (e.g.
`ENABLE_APP_SANDBOX`) require editing `project.pbxproj` text directly.

---

## Platform & Deployment Support

- macOS only, one universal app target, deployment target 26.5 (Xcode 26.6 toolchain).
- **Not sandboxed** (`ENABLE_APP_SANDBOX = NO`) — required because the app shells out to
  package managers and reads other apps' bundles/receipts, which the App Sandbox forbids. No
  `.entitlements` file exists (none needed currently; `GENERATE_INFOPLIST_FILE = YES` auto-
  generates `Info.plist`).
- **Hardened Runtime is ON** (`ENABLE_HARDENED_RUNTIME = YES`) in preparation for future
  Developer ID notarization.
- **Not distributed via the Mac App Store** (can't be, given the above) — intended distribution
  is Developer ID signing + notarization, which is **not yet done**; it requires the user's own
  Apple Developer account action and can't be completed by an AI assistant alone.
- Bundle ID `com.Hrithik.AppX-Manager`, Team `TC7L7V5P7N`.

---

## Features

### 1. Homebrew (formula + cask) scanning & updating

`Engines/HomebrewScanner.swift` (`brew list --formula/--cask --versions` + `brew outdated
--json=v2`, decoded via `HomebrewScanner.OutdatedResponse`) + `Updaters/HomebrewUpdater.swift`
(`brew upgrade [--cask] <name>`, 900s timeout). Cask app paths are resolved via `brew info
--cask --json=v2 <token>`'s `artifacts[].app[]`, falling back to the Caskroom metadata directory
for CLI-only casks with no `app` artifact.

### 2. Dev tools: npm / pip / gem global packages

`Engines/NpmScanner.swift`, `PipScanner.swift`, `GemScanner.swift` + matching `Updaters/`. All 3
map to the single `Source.devTools` UI bucket (a deliberate decision — the dashboard's sidebar
has 4 fixed source filters, not 6). `PipScanner` resolves `pip3`, falling back to `python3 -m
pip`. `GemScanner.parseList`/`parseOutdated` are plain-text regex-free parsers (covered by the
only real unit tests in the repo).

### 3. Mac App Store apps

`Engines/MasScanner.swift` discovers installed App Store apps via each app's own
`Contents/_MASReceipt/receipt` file — this works with **zero dependency on the `mas` CLI**. The
`mas` CLI (if installed) is used *additionally*, only for `mas outdated` (never `mas list`,
which is confirmed to hang indefinitely) to check for available updates; every `mas` call
degrades gracefully (`isMasCLIAvailable = false`) rather than failing the whole scan, since
`mas` relies on undocumented App Store internals that can break after macOS updates.
`Updaters/MasUpdater.swift` runs `mas upgrade <app-id>`.

### 4. Direct-download app detection

Three-stage classification per `/Applications/*.app` not already claimed by Homebrew/App Store,
run concurrently across all apps (`SparkleScanner.scan()`'s `withTaskGroup`):
1. **Sparkle** (`SparkleScanner.swift`): reads `SUFeedURL` from `Info.plist`, fetches + parses
   the appcast XML (`XMLParser`), compares to `CFBundleVersion`. "Update" opens the app so its
   own Sparkle updater can run (see [lifecycle #2](#key-runtime-lifecycle-2--single-item-update)).
2. **Homebrew cask fallback** (`CaskFallbackMatcher.swift`, an `actor` singleton): matches by
   app/artifact filename or cask display name against the public cask catalog (not bundle ID —
   that field isn't reliably present in that API). A match surfaces an explicit "Adopt…" action
   (never a silent takeover) that runs `brew install --cask <token> --force` and re-homes the
   item under Homebrew going forward.
3. **App Store homepage lookup** (`AppStoreLookup.swift`, added 2026-08-17): for apps still
   unmatched after 1–2, queries the public iTunes Search API and trusts a result **only** if its
   `bundleId` exactly matches the installed app's real bundle identifier — populates
   `homepageURL` (for a "Visit site" link) but never a version/update path. See
   [Legacy Notes](#legacy-notes--caveats) for why name-only matching was rejected.

### 5. Dashboard UI

`UI/Dashboard/{DashboardView,SidebarView,AppRowView,DetailPanelView,BatchProgressBar}.swift`.
Sidebar filters: All / Needs update / Updating (shown only when non-empty) / per-`Source`.
Toolbar: search, sort (Name/Size/Status, ascending/descending), debug-log reveal button,
last-scanned timestamp, Update selected / Rescan / Update all. Row action column has 5 states
(Update / Updating spinner / Failed+Retry / Up to date badge / Visit site or plain "Unknown").
Detail panel slides in from the trailing edge, dismissible by tapping anywhere outside it (an
invisible near-zero-opacity tap-catcher layered behind it).

### 6. Onboarding

`UI/Onboarding/OnboardingView.swift` — 3 steps: welcome, Full Disk Access (real System Settings
deep link via `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`, then
a manual "I've granted access" button since there's no API to verify the grant), and an
explanation that every update is user-approved (deliberately **not** a real Automation/TCC
permission request — Foundation `Process` shell-outs don't trigger that prompt, so the copy was
written to describe in-app approval instead of claiming an OS permission that isn't actually
requested).

### 7. Debug logging

`Support/DebugLog.swift` — append-only log of every shelled-out command plus update/adopt
lifecycle events, revealed via a toolbar bug-icon button
(`NSWorkspace.shared.activateFileViewerSelecting`). This is the primary diagnostic tool for this
app in practice — real bugs this session (cancelled network fetches, a scan race condition,
duplicate cask-catalog fetches) were all root-caused from this log, not from screenshots or a
live debugger.

---

## Security

No auth/credentials/session management exists (single local user, no accounts). Relevant
points instead:

- **App Sandbox is deliberately off.** This is a considered tradeoff, not an oversight — the
  app's entire purpose (shelling out to package managers, reading other apps' bundles) is
  fundamentally incompatible with the sandbox. Hardened Runtime is kept on as a partial
  mitigation and for future notarization.
- **No shell-injection risk in `ShellRunner`**: every spawn goes through `/usr/bin/env
  <name> args...` with arguments passed as a `[String]` array to `Process.arguments` — never
  concatenated into an interpretable shell string, so there's no command-injection surface even
  though arbitrary app/package names (which could theoretically contain shell metacharacters)
  flow into these calls.
- **3 outbound network calls**, all read-only HTTPS GETs, no credentials attached:
  `formulae.brew.sh/api/cask.json` (Homebrew's public catalog), each app's own `SUFeedURL`
  (from its *own* `Info.plist` — inherently as trustworthy as the app itself, only ever parsed
  for a version string, never executed), and `itunes.apple.com/search` (Apple's public search
  API). None send personal/user-identifying data — only app names and bundle identifiers
  (public identifiers), which is why the onboarding copy's "nothing ever leaves your Mac" claim
  is flagged in [Legacy Notes](#legacy-notes--caveats) as now slightly imprecise.
- **Full Disk Access** is requested (needed to read other apps' `Info.plist`/receipts and
  package-manager directories) but its grant is never programmatically verified — there's no
  public API for that; the UI takes the user's word via a manual "I've granted access" button.

---

## Privacy

- **Reads**: `/Applications` folder contents, Homebrew/npm/pip/gem package manifests, Mac App
  Store receipt files, other installed apps' `Info.plist` files. All metadata about installed
  software — never user document content.
- **No analytics/telemetry** of any kind.
- **No data leaves the Mac** except the 3 read-only outbound calls described in
  [Security](#security) — none of which carry personal data, only app names/bundle IDs.

---

## Legacy Notes & Caveats

- **Onboarding copy is now slightly stale.** `OnboardingView`'s Full Disk Access step says
  "nothing ever leaves your Mac" — no longer fully precise now that 3 outbound API calls exist
  for update-checking (cask catalog / Sparkle appcast / iTunes lookup). None send personal data,
  but the literal phrasing overclaims. Flagged here rather than silently rewritten, since it's a
  product-copy call, not a bug fix.
- **Packaging (Developer ID signing + notarization) is not done.** Hardened Runtime is on in
  preparation, but actual signing-identity setup and `notarytool` submission need the user's own
  Apple Developer account action.
- **Adapters for `Updaters/*.swift` live inside `ScanEngine.swift`**, not in `Updaters/` itself
  — a minor, deliberate deviation from the one-type-per-file convention used everywhere else in
  the codebase. Worth knowing so it isn't "rediscovered" as confusing later.
- **`AppX ManagerUITests` has zero real assertions** — it's Xcode's unfilled default stub. Don't
  mistake "a UI test target exists" for "UI test coverage exists."
- **Test coverage is narrow by design/necessity, not an oversight**: the only 4 tests cover pure
  text/JSON parsing (`GemScanner`, `HomebrewScanner`'s decoder) — nothing exercises
  `ShellRunner`, `ScanEngine`'s concurrency/race behavior, any UI, or the other 4 scanners/5
  updaters live. See `SDLC.md` § "What verify means in this codebase" for what substitutes for
  this today.
- **Hard-won concurrency gotchas from real debugging sessions** (worth internalizing before
  touching `ScanEngine`/`SparkleScanner`/`CaskFallbackMatcher` again):
  - A slow/network `await` reached from `RootView`'s `.task(id: screen)` chain is at risk of
    silent cancellation with no error surfaced beyond `URLError` "cancelled" — this cost real
    debugging time before `Task.detached` was adopted as the fix in 3 places. If a *new*
    scanner/feature adds a slow network or process call and results come back suspiciously
    empty/uniform, suspect cancellation before suspecting the data source.
  - Turning a sequential scan loop concurrent (`withTaskGroup`) silently exposed a real data
    race in `CaskFallbackMatcher`'s previously-unsynchronized `static var` cache — before
    parallelizing *any* loop, audit every callee for shared mutable state first.
  - A hand-rolled `Circle().trim().rotationEffect()` spinner driven by
    `withAnimation(...repeatForever...)` in `.onAppear` (previously in `ScanningView`) gets
    silently interrupted/frozen by ANY re-render of its parent view while in flight — and that
    view re-rendered on every scan-step change, i.e. constantly during a real scan. Replaced
    with the native `ProgressView` circular style, whose animation is owned by the system
    control and immune to this. Prefer `ProgressView` over hand-rolled `repeatForever` animations
    in any view that re-renders on a frequently-changing `@Observable` property.
  - A `guard !isScanning else { return }` re-entrancy guard on `ScanEngine.scan()` (meant to
    stop a scan from running twice concurrently) introduced a *worse* bug: a second concurrent
    caller returned instantly as if done, so `RootView` navigated to a still-empty Dashboard.
    Replaced with in-flight `Task` de-duplication (current code) — see
    [Design patterns](#design-patterns-in-use).
- **iTunes Search API name-only matching was tested and rejected as unsafe**: searching
  "Discord" or "Notion" by name alone returns unrelated third-party wrapper apps with completely
  different developers/bundle IDs (verified live via `curl`), since the real apps aren't on the
  Mac App Store at all. `AppStoreLookup` only trusts a result whose `bundleId` exactly matches
  the installed app's own real bundle identifier — do not loosen this to name/developer
  similarity if extending this feature.
