//
//  ScanEngine.swift
//  AppX Manager
//

import Foundation
import Observation
import AppKit

enum ScanStep: CaseIterable {
    case applications, appStore, homebrew, npm, pip, gem

    var label: String {
        switch self {
        case .applications: "Applications folder"
        case .appStore: "App Store receipts"
        case .homebrew: "Homebrew"
        case .npm: "npm global packages"
        case .pip: "pip packages"
        case .gem: "gem packages"
        }
    }
}

protocol ItemUpdating {
    func update(_ item: InstalledItem) async throws
}

/// Orchestrates every source scanner and updater, and owns all dashboard-facing
/// state (items, per-source scan progress, single/batch update state).
@MainActor
@Observable
final class ScanEngine {
    private(set) var items: [InstalledItem] = []
    private(set) var completedSteps: Set<ScanStep> = []
    private(set) var currentStep: ScanStep?
    private(set) var isScanning = false
    private(set) var lastScanned: Date?
    private(set) var homebrewAvailable = true
    private(set) var masAvailable = true

    private(set) var updatingIDs: Set<String> = []
    private(set) var failedIDs: Set<String> = []
    private(set) var batchTotal = 0
    private(set) var batchDone = 0
    var isBatchUpdating: Bool { batchTotal > 0 }

    private let updateConcurrencyLimit = 3
    private var inFlightScan: Task<Void, Never>?

    // MARK: - Scanning

    /// Runs each source sequentially so the Scanning screen can show one active
    /// step at a time, matching the design (spec §7's "sequentially marks each
    /// source as done"). Safe to call concurrently/redundantly (e.g. a rescan
    /// tap landing while an appear-driven scan is already in flight) — a second
    /// caller AWAITS the same in-progress scan instead of either duplicating
    /// the work or (the previous bug) returning immediately with stale/empty
    /// results while the real scan is still running, which made the caller
    /// navigate to a still-empty dashboard.
    func scan() async {
        if let inFlightScan {
            await inFlightScan.value
            return
        }
        let task = Task { await performScan() }
        inFlightScan = task
        await task.value
        inFlightScan = nil
    }

    private func performScan() async {
        isScanning = true
        completedSteps = []

        currentStep = .appStore
        let masItems = await MasScanner.scan()
        masAvailable = MasScanner.isMasCLIAvailable
        completedSteps.insert(.appStore)

        currentStep = .homebrew
        let homebrewItems = await HomebrewScanner.scan()
        homebrewAvailable = HomebrewScanner.isAvailable
        completedSteps.insert(.homebrew)

        currentStep = .npm
        let npmItems = await NpmScanner.scan()
        completedSteps.insert(.npm)

        currentStep = .pip
        let pipItems = await PipScanner.scan()
        completedSteps.insert(.pip)

        currentStep = .gem
        let gemItems = await GemScanner.scan()
        completedSteps.insert(.gem)

        currentStep = .applications
        let excludedBundleIds = Set(masItems.map(\.bundleId))
        let excludedPaths = Set(homebrewItems.filter { $0.provider == .homebrewCask }.map(\.path))
        let directItems = await SparkleScanner.scan(excludingBundleIds: excludedBundleIds, excludingPaths: excludedPaths)
        completedSteps.insert(.applications)

        items = masItems + homebrewItems + npmItems + pipItems + gemItems + directItems
        lastScanned = Date()
        currentStep = nil
        isScanning = false
    }

    // MARK: - Single-item updates

    func update(_ id: String) async {
        await performUpdate(id)
    }

    func retry(_ id: String) async {
        failedIDs.remove(id)
        await performUpdate(id)
    }

    private func performUpdate(_ id: String) async {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items[index]
        failedIDs.remove(id)
        updatingIDs.insert(id)
        items[index].status = .updating
        DebugLog.log("UPDATE START: \(item.name) [\(item.provider)] \(item.installedVersion) -> \(item.latestVersion ?? "?")")

        do {
            try await updater(for: item.provider).update(item)
            if let refreshedIndex = items.firstIndex(where: { $0.id == id }) {
                // Opening a Sparkle app doesn't confirm the update actually ran —
                // leave its status alone rather than claiming a false success.
                if item.provider != .sparkle {
                    items[refreshedIndex].status = .upToDate
                    items[refreshedIndex].installedVersion = item.latestVersion ?? item.installedVersion
                } else {
                    items[refreshedIndex].status = .updateAvailable
                }
            }
            DebugLog.log(item.provider == .sparkle ? "OPENED (sparkle, not confirmed updated): \(item.name)" : "UPDATE SUCCEEDED: \(item.name)")
        } catch {
            if let refreshedIndex = items.firstIndex(where: { $0.id == id }) {
                items[refreshedIndex].status = .failed
            }
            failedIDs.insert(id)
            DebugLog.log("UPDATE FAILED: \(item.name) — \(error.localizedDescription)")
        }
        updatingIDs.remove(id)
    }

    private func updater(for provider: Provider) -> any ItemUpdating {
        switch provider {
        case .homebrewFormula, .homebrewCask: HomebrewUpdaterAdapter()
        case .npm: NpmUpdaterAdapter()
        case .pip: PipUpdaterAdapter()
        case .gem: GemUpdaterAdapter()
        case .appStore: MasUpdaterAdapter()
        case .sparkle: SparkleUpdaterAdapter()
        case .caskFallback, .unmanaged: UnsupportedUpdaterAdapter()
        }
    }

    // MARK: - Batch updates

    /// Sparkle apps open their own updater UI (shouldn't happen unattended in a
    /// batch) and cask-fallback matches require the explicit "Adopt" action first
    /// — neither belongs in an automatic Update All/Selected run.
    private func isBatchUpdatable(_ item: InstalledItem) -> Bool {
        item.status == .updateAvailable && item.provider != .sparkle && item.provider != .caskFallback
    }

    func updateAll() async {
        let ids = items.filter { isBatchUpdatable($0) }.map(\.id)
        await runBatch(ids)
    }

    func updateSelected(_ ids: Set<String>) async {
        let updatable = items.filter { ids.contains($0.id) && isBatchUpdatable($0) }.map(\.id)
        await runBatch(updatable)
    }

    private func runBatch(_ ids: [String]) async {
        guard !ids.isEmpty else { return }
        batchTotal = ids.count
        batchDone = 0

        var queue = ids
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<min(updateConcurrencyLimit, queue.count) {
                let id = queue.removeFirst()
                group.addTask { await self.performUpdate(id) }
            }
            while await group.next() != nil {
                batchDone += 1
                if !queue.isEmpty {
                    let id = queue.removeFirst()
                    group.addTask { await self.performUpdate(id) }
                }
            }
        }
        batchTotal = 0
        batchDone = 0
    }

    // MARK: - Direct-download adoption

    /// Explicit opt-in action (spec §8) — never adopted silently.
    func adoptIntoHomebrew(_ id: String) async {
        guard let index = items.firstIndex(where: { $0.id == id }), let token = items[index].caskToken else { return }
        failedIDs.remove(id)
        updatingIDs.insert(id)
        defer { updatingIDs.remove(id) }
        do {
            let result = try await ShellRunner.run("brew", ["install", "--cask", token, "--force"], timeout: 900)
            guard result.exitCode == 0 else { throw UpdaterError.commandFailed(result.stderr) }
            items[index].provider = .homebrewCask
            items[index].source = .homebrew
            items[index].status = .upToDate
            if let latest = items[index].latestVersion {
                items[index].installedVersion = latest
            }
            DebugLog.log("ADOPT SUCCEEDED: \(items[index].name) -> homebrew cask \(token)")
        } catch {
            failedIDs.insert(id)
            DebugLog.log("ADOPT FAILED: cask \(token) — \(error.localizedDescription)")
        }
    }

    /// User-triggered install of the `mas` CLI via Homebrew, then a full rescan
    /// so newly-checkable App Store apps pick up real update status.
    func installMasCLI() async {
        do {
            try await MasScanner.installCLI()
            await scan()
        } catch {
            masAvailable = false
        }
    }
}

private struct HomebrewUpdaterAdapter: ItemUpdating {
    func update(_ item: InstalledItem) async throws { try await HomebrewUpdater.update(item) }
}
private struct NpmUpdaterAdapter: ItemUpdating {
    func update(_ item: InstalledItem) async throws { try await NpmUpdater.update(item) }
}
private struct PipUpdaterAdapter: ItemUpdating {
    func update(_ item: InstalledItem) async throws { try await PipUpdater.update(item) }
}
private struct GemUpdaterAdapter: ItemUpdating {
    func update(_ item: InstalledItem) async throws { try await GemUpdater.update(item) }
}
private struct MasUpdaterAdapter: ItemUpdating {
    func update(_ item: InstalledItem) async throws { try await MasUpdater.update(item) }
}
/// Sparkle-based apps ship their own in-app updater — the cleanest, most
/// reliable path is to launch the app itself rather than reimplement its
/// installation (spec §8), so "Update" here just opens it.
private struct SparkleUpdaterAdapter: ItemUpdating {
    func update(_ item: InstalledItem) async throws {
        guard NSWorkspace.shared.open(URL(fileURLWithPath: item.path)) else {
            throw UpdaterError.commandFailed("Couldn't open \(item.name).")
        }
    }
}
private struct UnsupportedUpdaterAdapter: ItemUpdating {
    func update(_ item: InstalledItem) async throws { throw UpdaterError.unsupported }
}
