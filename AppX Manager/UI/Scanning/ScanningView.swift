//
//  ScanningView.swift
//  AppX Manager
//

import SwiftUI

struct ScanningView: View {
    @Environment(\.colorScheme) private var colorScheme
    var scanEngine: ScanEngine

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        VStack(spacing: 6) {
            ProgressView()
                .controlSize(.large)
                .scaleEffect(1.4)
                .tint(palette.accent)
                .padding(.bottom, 14)

            Text("Scanning your Mac…")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(palette.text)
            Text("This usually takes less than a minute.")
                .font(.system(size: 13))
                .foregroundStyle(palette.textSecondary)
                .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(ScanStep.allCases, id: \.self) { step in
                    HStack(spacing: 10) {
                        stepIcon(for: step, palette: palette)
                            .frame(width: 18, height: 18)
                        Text(step.label)
                            .font(.system(size: 13))
                            .foregroundStyle(
                                scanEngine.completedSteps.contains(step) || scanEngine.currentStep == step
                                    ? palette.text : palette.textTertiary
                            )
                    }
                }
            }
            .frame(width: 340, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.windowBackground)
    }

    @ViewBuilder
    private func stepIcon(for step: ScanStep, palette: Theme.Palette) -> some View {
        if scanEngine.completedSteps.contains(step) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.accent)
        } else if scanEngine.currentStep == step {
            ProgressView()
                .controlSize(.small)
                .tint(palette.accent)
        } else {
            Circle()
                .fill(palette.textTertiary)
                .frame(width: 4, height: 4)
        }
    }
}

#Preview {
    ScanningView(scanEngine: ScanEngine())
}
