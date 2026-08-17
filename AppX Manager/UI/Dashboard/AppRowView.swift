//
//  AppRowView.swift
//  AppX Manager
//

import SwiftUI

struct AppRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: InstalledItem
    let isSelected: Bool
    let isUpdating: Bool
    let isFailed: Bool
    let onToggleSelect: () -> Void
    let onOpen: () -> Void
    let onUpdate: () -> Void
    let onRetry: () -> Void
    let onVisitSite: () -> Void
    let onAdopt: () -> Void

    @State private var showAdoptConfirmation = false

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
        item.sizeBytes > 0 ? ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file) : "—"
    }

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        HStack(spacing: 12) {
            Button(action: onToggleSelect) {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isSelected ? palette.accent : palette.borderStrong, lineWidth: 1.3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(isSelected ? palette.accent : .clear))
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .frame(width: Theme.Layout.rowCheckboxWidth)

            Text(initials)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: Theme.Layout.rowIconSize, height: Theme.Layout.rowIconSize)
                .background(sourceTint, in: RoundedRectangle(cornerRadius: 8))
                .frame(width: Theme.Layout.rowIconWidth)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                Text(item.description)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                Text(item.source.rawValue)
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(palette.tagBackground, in: RoundedRectangle(cornerRadius: 4))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(formattedSize)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .frame(width: Theme.Layout.rowSizeWidth, alignment: .trailing)

            Text(item.installedVersion)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(item.installedVersion)
                .frame(width: Theme.Layout.rowInstalledWidth, alignment: .trailing)

            Group {
                if item.status == .unknown {
                    Text("Unknown")
                        .italic()
                        .foregroundStyle(palette.textTertiary)
                } else {
                    Text(item.latestVersion ?? item.installedVersion)
                        .foregroundStyle(palette.text)
                }
            }
            .font(.system(size: 12, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.tail)
            .help(item.latestVersion ?? item.installedVersion)
            .frame(width: Theme.Layout.rowLatestWidth, alignment: .trailing)

            actionColumn(palette: palette)
                .frame(width: Theme.Layout.rowActionWidth, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(isSelected ? palette.rowSelectedBackground : Color.clear)
        .onTapGesture(perform: onOpen)
        .confirmationDialog(
            "Adopt \(item.name) into Homebrew?",
            isPresented: $showAdoptConfirmation,
            titleVisibility: .visible
        ) {
            Button("Adopt", action: onAdopt)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Future updates for \(item.name) will run through Homebrew instead of its original installer.")
        }
    }

    @ViewBuilder
    private func actionColumn(palette: Theme.Palette) -> some View {
        if isUpdating {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(palette.accent)
                Text("Updating…").font(.system(size: 12)).foregroundStyle(palette.textSecondary)
            }
        } else if isFailed {
            HStack(spacing: 8) {
                Text("Update failed").font(.system(size: 12, weight: .medium)).foregroundStyle(palette.danger)
                Button("Retry", action: onRetry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        } else {
            switch item.status {
            case .updateAvailable where item.provider == .caskFallback:
                Button("Adopt…") { showAdoptConfirmation = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Match found in Homebrew — adopt to enable automatic updates.")
            case .updateAvailable:
                Button(item.provider == .sparkle ? "Open to Update" : "Update", action: onUpdate)
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                    .controlSize(.small)
                    .help(item.provider == .sparkle ? "AppX Manager can't update \(item.name) directly — this opens it so its built-in updater can run." : "Update")
            case .upToDate:
                Text("Up to date")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(palette.rowSelectedBackground, in: RoundedRectangle(cornerRadius: 5))
            case .unknown:
                if item.homepageURL != nil {
                    Button("Visit site", action: onVisitSite)
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.accent)
                } else {
                    Text(item.provider == .appStore ? "Install mas to check" : "Unknown")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.textTertiary)
                }
            case .updating, .failed:
                EmptyView()
            }
        }
    }
}

#Preview {
    AppRowView(
        item: InstalledItem(
            id: "preview", name: "Xcode", description: "Apple's IDE", source: .appStore, provider: .appStore,
            developer: "Apple", installedVersion: "16.0", latestVersion: "16.1", status: .updateAvailable,
            sizeBytes: 0, installDate: .now, bundleId: "com.apple.dt.Xcode", path: "/Applications/Xcode.app",
            history: [], homepageURL: nil
        ),
        isSelected: false, isUpdating: false, isFailed: false,
        onToggleSelect: {}, onOpen: {}, onUpdate: {}, onRetry: {}, onVisitSite: {}, onAdopt: {}
    )
}

