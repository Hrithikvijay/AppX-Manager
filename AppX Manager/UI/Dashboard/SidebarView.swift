//
//  SidebarView.swift
//  AppX Manager
//

import SwiftUI

struct SidebarView: View {
    @Environment(\.colorScheme) private var colorScheme
    let items: [InstalledItem]
    @Binding var filter: SidebarFilter
    let needsUpdateCount: Int
    let updatingCount: Int

    private var sourceCounts: [Source: Int] {
        Dictionary(grouping: items, by: \.source).mapValues(\.count)
    }

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        VStack(alignment: .leading, spacing: 0) {
            row(label: "All apps", glyph: "square.grid.2x2", tint: .gray, count: items.count, isSelected: filter == .all) {
                filter = .all
            }
            row(label: "Needs update", glyph: "exclamationmark", tint: palette.danger, count: needsUpdateCount, isSelected: filter == .needsUpdate, badgeIsAccent: true) {
                filter = .needsUpdate
            }
            if updatingCount > 0 {
                row(label: "Updating", glyph: "arrow.triangle.2.circlepath", tint: palette.accent, count: updatingCount, isSelected: filter == .updating) {
                    filter = .updating
                }
            }

            Divider()
                .overlay(palette.border)
                .padding(.vertical, 10)
                .padding(.horizontal, 16)

            Text("SOURCES")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, 18)
                .padding(.bottom, 4)

            ForEach(Source.allCases, id: \.self) { source in
                row(
                    label: source.rawValue,
                    glyph: glyph(for: source),
                    tint: tint(for: source),
                    count: sourceCounts[source] ?? 0,
                    isSelected: filter == .source(source)
                ) {
                    filter = .source(source)
                }
            }

            Spacer()
        }
        .padding(.vertical, 12)
        .frame(width: Theme.Layout.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(palette.sidebarBackground)
        .overlay(alignment: .trailing) { Divider().overlay(palette.border) }
    }

    private func glyph(for source: Source) -> String {
        switch source {
        case .appStore: "applelogo"
        case .homebrew: "command"
        case .direct: "arrow.down"
        case .devTools: "chevron.left.forwardslash.chevron.right"
        }
    }

    private func tint(for source: Source) -> Color {
        switch source {
        case .appStore: Theme.SourceColor.appStore
        case .homebrew: Theme.SourceColor.homebrew
        case .direct: Theme.SourceColor.directDownload
        case .devTools: Theme.SourceColor.devTools
        }
    }

    @ViewBuilder
    private func row(label: String, glyph: String, tint: Color, count: Int, isSelected: Bool, badgeIsAccent: Bool = false, action: @escaping () -> Void) -> some View {
        let palette = Theme.palette(for: colorScheme)
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: glyph)
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(tint, in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? palette.accent : palette.text)
                Spacer()
                if badgeIsAccent && count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(palette.danger, in: Capsule())
                } else {
                    Text("\(count)")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(isSelected ? palette.rowSelectedBackground : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
}

#Preview {
    SidebarView(items: [], filter: .constant(.all), needsUpdateCount: 0, updatingCount: 0)
}
