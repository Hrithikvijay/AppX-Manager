//
//  DetailPanelView.swift
//  AppX Manager
//

import SwiftUI
import AppKit

struct DetailPanelView: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: InstalledItem
    let isUpdating: Bool
    let onClose: () -> Void
    let onUpdate: () -> Void
    let onAdopt: () -> Void

    @State private var showUninstallConfirmation = false

    private var initials: String {
        let letters = item.name.filter(\.isLetter).prefix(2)
        return letters.isEmpty ? String(item.name.prefix(1)).uppercased() : letters.uppercased()
    }

    private var sourceTint: Color {
        switch item.source {
        case .appStore: Theme.SourceColor.appStore
        case .homebrew: Theme.SourceColor.homebrew
        case .direct: Theme.SourceColor.directDownload
        case .devTools: Theme.SourceColor.devTools
        }
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file)
    }

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(palette.textSecondary)
                            .frame(width: 22, height: 22)
                            .background(palette.chipBackground, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                Text(initials)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(sourceTint, in: RoundedRectangle(cornerRadius: 14))
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 12)

                Text(item.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.text)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("\(item.developer) · \(item.source.rawValue)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 16)

                actionRow(palette: palette)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 16)

                Divider().overlay(palette.border).padding(.vertical, 6)

                infoRow(label: "Installed version", value: item.installedVersion, palette: palette)
                infoRow(label: "Latest version", value: item.status == .unknown ? "Unknown" : (item.latestVersion ?? item.installedVersion), palette: palette)
                infoRow(label: "Install date", value: item.installDate.formatted(date: .abbreviated, time: .omitted), palette: palette)
                infoRow(label: "Install source", value: item.source.rawValue, palette: palette)
                infoRow(label: "Disk size", value: formattedSize, palette: palette)

                Divider().overlay(palette.border).padding(.vertical, 6)

                sectionLabel("Bundle identifier", palette: palette)
                Text(item.bundleId)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(palette.text)
                    .textSelection(.enabled)
                    .padding(.bottom, 8)

                sectionLabel("Install path", palette: palette)
                Text(item.path)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(palette.text)
                    .textSelection(.enabled)
                    .padding(.bottom, 8)

                Divider().overlay(palette.border).padding(.vertical, 6)

                sectionLabel("Version history", palette: palette)
                if item.history.isEmpty {
                    historyRow(version: "Unavailable", date: "—", palette: palette)
                } else {
                    ForEach(item.history) { entry in
                        historyRow(version: entry.version, date: entry.date.formatted(date: .abbreviated, time: .omitted), palette: palette)
                    }
                }

                Divider().overlay(palette.border).padding(.vertical, 6)

                HStack(spacing: 8) {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "")
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                    Button("Uninstall", role: .destructive) {
                        showUninstallConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 8)
            }
            .padding(24)
        }
        .frame(width: Theme.Layout.detailPanelWidth)
        .frame(maxHeight: .infinity)
        .background(palette.panelBackground)
        .overlay(alignment: .leading) { Divider().overlay(palette.border) }
        .confirmationDialog(
            "Uninstall \(item.name)?",
            isPresented: $showUninstallConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) { uninstall() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This moves \(item.name) to the Trash. This can't be undone from within AppX Manager.")
        }
    }

    @ViewBuilder
    private func actionRow(palette: Theme.Palette) -> some View {
        if isUpdating {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Updating…").font(.system(size: 13)).foregroundStyle(palette.textSecondary)
            }
        } else if item.status == .updateAvailable && item.provider == .sparkle {
            VStack(spacing: 8) {
                Text("AppX Manager can't update this app directly — it manages its own updates internally.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.textTertiary)
                    .multilineTextAlignment(.center)
                Button("Open \(item.name) to Update", action: onUpdate)
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
            }
        } else if item.status == .updateAvailable {
            Button("Update to \(item.latestVersion ?? "latest")", action: onUpdate)
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
        } else if item.status == .upToDate {
            Text("Up to date")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(palette.rowSelectedBackground, in: RoundedRectangle(cornerRadius: 6))
        } else if item.provider == .caskFallback {
            VStack(spacing: 8) {
                Text("Matched to a Homebrew cask — adopt it to get automatic updates.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.textTertiary)
                    .multilineTextAlignment(.center)
                Button("Adopt into Homebrew", action: onAdopt)
                    .buttonStyle(.bordered)
            }
        } else {
            Text("Version unknown — visit developer site")
                .font(.system(size: 12))
                .foregroundStyle(palette.textTertiary)
        }
    }

    private func infoRow(label: String, value: String, palette: Theme.Palette) -> some View {
        HStack {
            Text(label).font(.system(size: 12.5)).foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(value)
        }
        .padding(.vertical, 4)
    }

    private func sectionLabel(_ text: String, palette: Theme.Palette) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(palette.textTertiary)
            .padding(.top, 6)
            .padding(.bottom, 4)
    }

    private func historyRow(version: String, date: String, palette: Theme.Palette) -> some View {
        HStack {
            Text(version).font(.system(size: 12, weight: .medium)).foregroundStyle(palette.text)
            Spacer()
            Text(date).font(.system(size: 12)).foregroundStyle(palette.textTertiary)
        }
        .padding(.vertical, 3)
    }

    private func uninstall() {
        let url = URL(fileURLWithPath: item.path)
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        onClose()
    }
}

#Preview {
    DetailPanelView(
        item: InstalledItem(
            id: "preview", name: "Xcode", description: "Apple's IDE", source: .appStore, provider: .appStore,
            developer: "Apple", installedVersion: "16.0", latestVersion: "16.1", status: .updateAvailable,
            sizeBytes: 12_000_000_000, installDate: .now, bundleId: "com.apple.dt.Xcode", path: "/Applications/Xcode.app",
            history: [], homepageURL: nil
        ),
        isUpdating: false, onClose: {}, onUpdate: {}, onAdopt: {}
    )
}
