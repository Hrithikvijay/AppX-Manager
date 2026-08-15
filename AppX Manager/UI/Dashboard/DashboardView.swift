//
//  DashboardView.swift
//  AppX Manager
//

import SwiftUI
import AppKit

enum SidebarFilter: Hashable {
    case all
    case needsUpdate
    case source(Source)
}

struct DashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    var scanEngine: ScanEngine
    var onRescan: () -> Void

    @State private var filter: SidebarFilter = .all
    @State private var searchQuery = ""
    @State private var selectedIDs: Set<String> = []
    @State private var detailItemID: String?

    private var filteredItems: [InstalledItem] {
        var result = scanEngine.items
        switch filter {
        case .all: break
        case .needsUpdate: result = result.filter { $0.status == .updateAvailable }
        case .source(let source): result = result.filter { $0.source == source }
        }
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter { $0.name.lowercased().contains(query) || $0.description.lowercased().contains(query) }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
                SidebarView(items: scanEngine.items, filter: $filter, needsUpdateCount: needsUpdateCount)

                VStack(spacing: 0) {
                    toolbar(palette: palette)

                    if scanEngine.isBatchUpdating {
                        BatchProgressBar(done: scanEngine.batchDone, total: scanEngine.batchTotal)
                    }

                    listHeader(palette: palette)

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredItems) { item in
                                VStack(spacing: 0) {
                                    AppRowView(
                                        item: item,
                                        isSelected: selectedIDs.contains(item.id),
                                        isUpdating: scanEngine.updatingIDs.contains(item.id),
                                        isFailed: scanEngine.failedIDs.contains(item.id),
                                        onToggleSelect: { toggleSelect(item.id) },
                                        onOpen: { detailItemID = item.id },
                                        onUpdate: { Task { await scanEngine.update(item.id) } },
                                        onRetry: { Task { await scanEngine.retry(item.id) } },
                                        onVisitSite: { if let url = item.homepageURL { NSWorkspace.shared.open(url) } }
                                    )
                                    Divider().overlay(palette.border)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.windowBackground)
            }

            if let detailItem {
                DetailPanelView(
                    item: detailItem,
                    isUpdating: scanEngine.updatingIDs.contains(detailItem.id),
                    onClose: { detailItemID = nil },
                    onUpdate: { Task { await scanEngine.update(detailItem.id) } },
                    onAdopt: { Task { await scanEngine.adoptIntoHomebrew(detailItem.id) } }
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

            Spacer()

            if let lastScanned = scanEngine.lastScanned {
                Text("Last scanned \(lastScanned.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textTertiary)
            }

            if selectedUpdatableCount > 0 {
                Button("Update selected (\(selectedUpdatableCount))") {
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
}

#Preview {
    DashboardView(scanEngine: ScanEngine(), onRescan: {})
}
