# SDLC — How We Work on AppX Manager

> Process + coding conventions + file placement. This is *rules* (how to act), distinct from
> *knowledge* (`architecture.md`) and behavioral rules (`../CLAUDE.md`).

---

## 1. Process

**Spec-first, execute-second.** Plan against the real source before writing code — don't assume
`architecture.md` is a substitute for reading the actual files. Prefer stating a short plan with
a verify step before multi-step changes.

**Source-grounded, no assumptions.** `architecture.md` is a snapshot as of its last verification
date (2026-08-17) — not a substitute for the live source. When it disagrees with the code, the
code wins, and the doc gets corrected. There are no closed-source/internal dependencies in this
app (zero third-party packages) — the only "black box" surface is the CLI tools it shells out to
(`brew`/`npm`/`pip`/`gem`/`mas`), whose real output shapes are documented in `architecture.md`'s
[Tech Stack](architecture.md#tech-stack) section from live verification, not guessed.

**Definition of done includes updating context.** After any change:
1. Update the relevant `features/<feature-name>.md` (create it from `_TEMPLATE.md` if this is
   the first time that feature has been touched with AI assistance).
2. Update the Feature status table in `INDEX.md` (state + date).
3. Run `prompts/update-context.md`'s ritual rather than hand-waving the update.

Stale context is worse than none, because tools act on it confidently.

---

## 2. Coding conventions — pinned invariants (do not relitigate)

**Concurrency:**
- Swift Concurrency (async/await) only — no Combine, no hand-written completion-handler APIs.
- New UI-facing state owners: `@MainActor @Observable` (Observation framework), matching
  `ScanEngine`. Do not introduce `ObservableObject`/`@Published`.
- New shared **mutable** state reachable from concurrent callers: use an `actor`, not a
  `static var` on an `enum`. `CaskFallbackMatcher` is the cautionary tale — an unsynchronized
  static cache caused a real data race once its callers became concurrent; it's now an actor
  with a shared singleton.
- Stateless per-source logic (a new scanner/updater): a plain `enum` with `static func`s,
  matching every existing `*Scanner`/`*Updater`.
- `Task.detached` is reserved for network/slow `await`s that must survive cancellation of the
  calling `.task(id:)` chain (3 existing uses: `CaskFallbackMatcher.catalog()`,
  `SparkleScanner.latestVersion(fromAppcast:)`, `AppStoreLookup.fetchHomepageURL`). Don't reach
  for it as a general "run in background" tool — it bypasses structured concurrency's
  cancellation/priority propagation.
- Blocking calls (`Process.waitUntilExit()`) run on a dedicated `DispatchQueue`
  (`ShellRunner.ioQueue`) via `withCheckedThrowingContinuation` — never `Task.detached`, which
  still shares Swift's cooperative thread pool and risks starving it.
- Before turning any sequential loop concurrent (`withTaskGroup`), audit every callee for
  unsynchronized shared mutable state first — this is how the `CaskFallbackMatcher` race got in.

**Architecture / patterns:**
- No ViewModel layer — views take `scanEngine: ScanEngine` directly and read/call it directly.
  Don't introduce a per-view ViewModel indirection; it doesn't match the rest of the codebase.
- `Provider` (not `Source`) is what routes an update to the right CLI — `Source` is purely the
  4-bucket UI/sidebar grouping (App Store / Homebrew / Direct download / Dev tools); npm, pip,
  and gem all share `Source.devTools` but are 3 different `Provider` cases. When adding a new
  update-capable source, add a `Provider` case and an `ItemUpdating` adapter in `ScanEngine.swift`
  — don't try to route by `Source` alone.
- Adapters (`HomebrewUpdaterAdapter` etc., wrapping each `Updaters/*.swift` enum into the common
  `ItemUpdating` protocol) live as private structs at the bottom of `ScanEngine.swift`, not in
  `Updaters/`. Match this placement for a new adapter rather than starting a new convention.
- Prefer the native `ProgressView` (circular style) over any hand-rolled
  `withAnimation(...repeatForever...)` spinner — the latter gets silently interrupted/frozen by
  re-renders of its parent view, which is a real, previously-shipped bug in this app.

**Persistence:**
- No database. The only persistent state is `@AppStorage("hasCompletedOnboarding")` and the
  `DebugLog` file. Don't introduce SwiftData/CoreData/a new UserDefaults key without a concrete
  need — this app's data is always a live scan result, never something that needs to survive
  being recomputed.

**Build / tooling:**
- Always open/build the `.xcodeproj` at `AppX Manager/AppX Manager.xcodeproj` (there's no
  `.xcworkspace` wrapping it — the project file itself is the right one).
- Always pass an explicit `-derivedDataPath "./.build"` to `xcodebuild` — the default
  `~/Library/Developer/Xcode/DerivedData` path is unreliable in some sandboxed terminal/agent
  environments and silently produces a stale build elsewhere otherwise.
- Uses `PBXFileSystemSynchronizedRootGroup` (all 3 targets) — adding/moving/deleting a source
  file on disk under a target's folder is auto-picked-up by Xcode. **No manual
  `project.pbxproj` group/file-reference edits are needed for source files** — only build-
  *setting* changes (e.g. `ENABLE_APP_SANDBOX`, a new build phase) require editing
  `project.pbxproj` text directly.
- **What "verify" means in this codebase**: there IS a real automated test suite
  (`AppX ManagerTests`, Swift Testing), but it's narrow — only `GemScanner` parsing and
  `HomebrewScanner`'s JSON decoder are covered. For anything in that surface, standard
  write-a-failing-test-first applies (fixture strings, hermetic, no live shell-outs — follow the
  existing tests' style). For everything else (the other 4 scanners, all 5 updaters,
  `ScanEngine`'s concurrency/state behavior, all UI), there is no automated coverage — verify via
  build success (`xcodebuild ... build`) plus a real manual run on an actual Mac, checking
  `~/Library/Application Support/AppX Manager/debug.log` for command-level evidence (this has
  been the single most effective diagnostic tool for this app in practice — check it before
  reaching for a screenshot or a live debugger).

---

## 3. File placement — where to save what

| Thing | Location |
|---|---|
| App source | `AppX Manager/AppX Manager/` (this repo — `AppX Manager/`, not the outer `AppsUpdater/` workspace wrapper) |
| AI context for a feature | `AI-Context/features/<feature-name>.md` |
| Deep architecture reference | `AI-Context/architecture.md` |
| Behavioral rules | `../CLAUDE.md` + `../.github/copilot-instructions.md` (identical, kept in sync) |
| The memory map / status | `AI-Context/INDEX.md` |
| Original pre-implementation build spec (historical reference only) | `../../design/AppX_Manager_BUILD_SPEC.md` (outside this repo, in the outer `AppsUpdater/` workspace folder — not version-controlled with the app) |
| Visual/design reference | `../../design/AppX Manager.dc.html` (same outer folder, same caveat) |

Never put substance (architecture, feature state, conventions) in the tool entry files. They
hold only the behavioral rules and a pointer into `AI-Context/`.

**Note on this repo's nesting**: the git repo root for AppX Manager is *this* folder
(`AppX Manager/`), which is itself nested one level inside the `AppsUpdater/` VS Code workspace
folder (which also holds `design/` and a thin pointer `.github/copilot-instructions.md` of its
own, for VS Code's auto-load — see that file's own header comment). Everything under
`AI-Context/` here is git-tracked and travels with this repo's commits; the outer `AppsUpdater/`
folder's own `design/`/`.github/` are a separate, non-git-tracked workspace convenience layer.

---

## 4. Working with the context docs

- Capture **invariants and decisions**, not volatile detail. File/class names are fine; line
  numbers and LOC counts rot — avoid pinning them as fact.
- Keep a **"What Didn't Work"** section in each feature file permanently — it's the guardrail
  against re-attempting known dead ends.
- When you correct a piece of wrong advice, say so explicitly and note what changed and why;
  don't silently revise.
- If a claim can't be verified against source, mark it `(unverified)` rather than asserting it.
