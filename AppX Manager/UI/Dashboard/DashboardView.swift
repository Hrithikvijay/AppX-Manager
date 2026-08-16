//
//  DashboardView.swift
//  AppX Manager
//

import SwiftUI
import AppKit

enum SidebarFilter: Hashable {
    case all
    case needsUpdate
    case updating
    case source(Source)
}

enum SortOption: String, CaseIterable, Identifiable {
    case name = "Name"
    case size = "Size"
    case status = "Status"
    var id: String { rawValue }
}

struct DashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    var scanEngine: ScanEngine
    var onRescan: () -> Void

    @State private var filter: SidebarFilter = .all
    @State private var searchQuery = ""
    @State private var selectedIDs: Set<String> = []
    @State private var detailItemID: String?
    @State private var sortOption: SortOption = .name
    @State private var sortAscending = true

    private var updatingCount: Int { scanEngine.updatingIDs.count }

    private var filteredItems: [InstalledItem] {
        var result: [InstalledItem]
        switch filter {
        case .all:
            result = scanEngine.items.filter { !scanEngine.updatingIDs.contains($0.id) }
        case .needsUpdate:
            result = scanEngine.items.filter { $0.status == .updateAvailable && !scanEngine.updatingIDs.contains($0.id) }
        case .updating:
            result = scanEngine.items.filter { scanEngine.updatingIDs.contains($0.id) }
        case .source(let source):
            result = scanEngine.items.filter { $0.source == source && !scanEngine.updatingIDs.contains($0.id) }
        }
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter { $0.name.lowercased().contains(query) || $0.description.lowercased().contains(query) }
        }
        return sorted(result)
    }

    private func sorted(_ items: [InstalledItem]) -> [InstalledItem] {
        let ascendingResult: [InstalledItem]
        switch sortOption {
        case .name:
            ascendingResult = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .size:
            ascendingResult = items.sorted { $0.sizeBytes < $1.sizeBytes }
        case .status:
            ascendingResult = items.sorted { statusSortRank($0.status) < statusSortRank($1.status) }
        }
        return sortAscending ? ascendingResult : Array(ascendingResult.reversed())
    }

    private func statusSortRank(_ status: UpdateStatus) -> Int {
        switch status {
        case .updateAvailable: 0
        case .failed: 1
        case .unknown: 2
        case .updating: 3
        case .upToDate: 4
        }
    }

    private var needsUpdateCount: Int {
        scanEngine.items.filter { $0.status == .updateAvailable }.count
    }

    private var detailItem: InstalledItem? {
        guard let detailItemID else { return nil }
        return scanEngine.items.first { $0.id == detailItemID }
    }

    private var selectedUpdatableCount: Int {
        selectedIDs.filter { id in scanEngine.items.first { $0.id == id }?.status == .updateAvailable }.count
    }

    var body: some View {
        let palette = Theme.palette(for: colorScheme)

        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                SidebarView(items: scanEngine.items, filter: $filter, needsUpdateCount: needsUpdateCount, updatingCount: updatingCount)

                VStack(spacing: 0) {
                    toolbar(palette: palette)

                    if !scanEngine.masAvailable {
                        masBanner(palette: palette)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if scanEngine.isBatchUpdating {
                        BatchProgressBar(done: scanEngine.batchDone, total: scanEngine.batchTotal)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    listHeader(palette: palette)
                        .fixedSize(horizontal: false, vertical: true)

                    if filteredItems.isEmpty {
                        emptyState(palette: palette)
                    } else {
                        List(filteredItems) { item in
                            VStack(spacing: 0) {
                                AppRowView(
                                    item: item,
                                    isSelected: selectedIDs.contains(item.id),
                                    isUpdating: scanEngine.updatingIDs.contains(item.id),
                                    isFailed: scanEngine.failedIDs.contains(item.id),
                                    onToggleSelect: { toggleSelect(item.id) },
                                    onOpen: { detailItemID = item.id },
                                    onUpdate: { startUpdate(item.id) },
                                    onRetry: { startUpdate(item.id, isRetry: true) },
                                    onVisitSite: { if let url = item.homepageURL { NSWorkspace.shared.open(url) } },
                                    onAdopt: { startAdopt(item.id) }
                                )
                                Divider().overlay(palette.border)
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .background(palette.windowBackground)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.windowBackground)
            }

            if detailItem != nil {
                Color.black.opacity(0.0001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { detailItemID = nil }
                    .zIndex(0.5)
            }

            if let detailItem {
                DetailPanelView(
                    item: detailItem,
                    isUpdating: scanEngine.updatingIDs.contains(detailItem.id),
                    onClose: { detailItemID = nil },
                    onUpdate: { startUpdate(detailItem.id) },
                    onAdopt: { startAdopt(detailItem.id) }
                )
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.2), value: detailItemID)
        .background(palette.windowBackground)
    }

    private func toggleSelect(_ id: String) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    /// Kicks off a single-item update and switches to the "Updating" tab so the
    /// in-flight item is easy to track instead of sitting unchanged in place.
    private func startUpdate(_ id: String, isRetry: Bool = false) {
        filter = .updating
        Task {
            if isRetry {
                await scanEngine.retry(id)
            } else {
                await scanEngine.update(id)
            }
        }
    }

    private func startAdopt(_ id: String) {
        filter = .updating
        Task { await scanEngine.adoptIntoHomebrew(id) }
    }

    @ViewBuilder
    private func toolbar(palette: Theme.Palette) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(palette.textTertiary)
                TextField("Search", text: $searchQuery)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .frame(width: 220, height: 30)
            .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 7))

            Menu {
                Picker("Sort by", selection: $sortOption) {
                    ForEach(SortOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                Button(sortAscending ? "Descending" : "Ascending") { sortAscending.toggle() }
            } label: {
                Label(sortOption.rawValue, systemImage: sortAscending ? "arrow.up.arrow.down" : "arrow.down.arrow.up")
                    .font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                DebugLog.revealInFinder()
            } label: {
                Image(systemName: "ladybug")
            }
            .buttonStyle(.borderless)
            .help("Reveal debug log in Finder")

            Spacer()

            if let lastScanned = scanEngine.lastScanned {
                Text("Last scanned \(lastScanned.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textTertiary)
            }

            if selectedUpdatableCount > 0 {
                Button("Update selected (\(selectedUpdatableCount))") {
                    filter = .updating
                    Task {
                        await scanEngine.updateSelected(selectedIDs)
                        selectedIDs.removeAll()
                    }
                }
                .buttonStyle(.bordered)
            }

            Button("⟲ Rescan", action: onRescan)
                .buttonStyle(.bordered)

            Button(needsUpdateCount == 0 ? "Update all" : "Update all (\(needsUpdateCount))") {
                filter = .updating
                Task { await scanEngine.updateAll() }
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.accent)
            .disabled(needsUpdateCount == 0 || scanEngine.isBatchUpdating)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Divider().overlay(palette.border) }
    }

    @ViewBuilder
    private func listHeader(palette: Theme.Palette) -> some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: Theme.Layout.rowCheckboxWidth)
            Color.clear.frame(width: Theme.Layout.rowIconWidth)
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Size")
                .frame(width: Theme.Layout.rowSizeWidth, alignment: .trailing)
            Text("Installed")
                .frame(width: Theme.Layout.rowInstalledWidth, alignment: .trailing)
            Text("Latest")
                .frame(width: Theme.Layout.rowLatestWidth, alignment: .trailing)
            Text("Status")
                .frame(width: Theme.Layout.rowActionWidth, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(palette.textTertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider().overlay(palette.borderStrong) }
    }

    @ViewBuilder
    private func masBanner(palette: Theme.Palette) -> some View {
        HStack(spacing: 12) {
            Text("`mas` isn't installed, so App Store update checks are unavailable.")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
            Spacer()
            Button("Install mas via Homebrew") {
                Task { await scanEngine.installMasCLI() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!scanEngine.homebrewAvailable)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider().overlay(palette.border) }
    }

    private var emptyStateMessage: String {
        switch filter {
        case .source(.appStore):
            "No Mac App Store apps detected on this Mac."
        case .source(let source):
            "No \(source.rawValue) apps match this view."
        case .needsUpdate:
            "Everything's up to date."
        case .updating:
            "Nothing is updating right now."
        case .all:
            "No apps found yet."
        }
    }

    @ViewBuilder
    private func emptyState(palette: Theme.Palette) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(palette.textTertiary)
            Text(emptyStateMessage)
                .font(.system(size: 13))
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    DashboardView(scanEngine: ScanEngine(), onRescan: {})
}

