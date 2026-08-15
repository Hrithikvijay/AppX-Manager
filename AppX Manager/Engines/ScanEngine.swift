//
//  ScanEngine.swift
//  AppX Manager
//

import Foundation
import Observation

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

    // MARK: - Scanning

    /// Runs each source sequentially so the Scanning screen can show one active
    /// step at a time, matching the design (spec §7's "sequentially marks each
    /// source as done").
    func scan() async {
        isScanning = true
        completedSteps = []

        currentStep = .appStore
        let masItems = await MasScanner.scan()
        masAvailable = MasScanner.isAvailable
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

        do {
            try await updater(for: item.provider).update(item)
            if let refreshedIndex = items.firstIndex(where: { $0.id == id }) {
                items[refreshedIndex].status = .upToDate
                items[refreshedIndex].installedVersion = item.latestVersion ?? item.installedVersion
            }
        } catch {
            if let refreshedIndex = items.firstIndex(where: { $0.id == id }) {
                items[refreshedIndex].status = .failed
            }
            failedIDs.insert(id)
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
        case .sparkle, .caskFallback, .unmanaged: UnsupportedUpdaterAdapter()
        }
    }

    // MARK: - Batch updates

    func updateAll() async {
        let ids = items.filter { $0.status == .updateAvailable }.map(\.id)
        await runBatch(ids)
    }

    func updateSelected(_ ids: Set<String>) async {
        let updatable = items.filter { ids.contains($0.id) && $0.status == .updateAvailable }.map(\.id)
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
        do {
            let result = try await ShellRunner.run("brew", ["install", "--cask", token, "--force"])
            guard result.exitCode == 0 else { throw UpdaterError.commandFailed(result.stderr) }
            items[index].provider = .homebrewCask
            items[index].source = .homebrew
            items[index].status = .upToDate
            if let latest = items[index].latestVersion {
                items[index].installedVersion = latest
            }
        } catch {
            failedIDs.insert(id)
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
private struct UnsupportedUpdaterAdapter: ItemUpdating {
    func update(_ item: InstalledItem) async throws { throw UpdaterError.unsupported }
}
