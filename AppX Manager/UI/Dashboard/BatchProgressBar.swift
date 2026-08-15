//
//  BatchProgressBar.swift
//  AppX Manager
//

import SwiftUI

struct BatchProgressBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let done: Int
    let total: Int

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        VStack(alignment: .leading, spacing: 6) {
            Text("Updating \(done) of \(total)…")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.border)
                    Capsule()
                        .fill(palette.accent)
                        .frame(width: total > 0 ? geometry.size.width * CGFloat(done) / CGFloat(total) : 0)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider().overlay(palette.border) }
    }
}

#Preview {
    BatchProgressBar(done: 2, total: 5)
}
