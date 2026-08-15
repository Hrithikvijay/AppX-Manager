//
//  OnboardingView.swift
//  AppX Manager
//

import SwiftUI
import AppKit

struct OnboardingView: View {
    @Environment(\.colorScheme) private var colorScheme
    let onComplete: () -> Void
    @State private var step = 0

    private let totalSteps = 3

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        let data = stepData(for: step)

        VStack(spacing: 4) {
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Circle()
                        .fill(index == step ? palette.accent : palette.border)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.bottom, 22)

            Text(data.icon)
                .font(.system(size: 24))
                .frame(width: 56, height: 56)
                .background(palette.accent, in: RoundedRectangle(cornerRadius: 14))
                .padding(.bottom, 18)

            Text(data.title)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(palette.text)
                .padding(.bottom, 10)

            Text(data.body)
                .font(.system(size: 13.5))
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)

            Text(data.note)
                .font(.system(size: 12))
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 26)

            HStack(spacing: 10) {
                if let secondaryLabel = data.secondaryLabel {
                    Button(secondaryLabel, action: data.onSecondary)
                        .buttonStyle(.bordered)
                }
                Button(data.primaryLabel, action: data.onPrimary)
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
            }
        }
        .padding(40)
        .frame(width: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.windowBackground)
        .multilineTextAlignment(.center)
    }

    private struct StepData {
        let icon: String
        let title: String
        let body: String
        let note: String
        let primaryLabel: String
        let onPrimary: () -> Void
        let secondaryLabel: String?
        let onSecondary: () -> Void
    }

    private func stepData(for step: Int) -> StepData {
        switch step {
        case 0:
            return StepData(
                icon: "⚙️",
                title: "Welcome to AppX Manager",
                body: "AppX Manager keeps every app, Homebrew formula, and dev tool package on your Mac up to date from one place — App Store apps, direct downloads, Homebrew, and npm, pip, and gem.",
                note: "Setup takes about a minute. One permission is needed to see everything installed.",
                primaryLabel: "Get Started",
                onPrimary: { self.step = 1 },
                secondaryLabel: nil,
                onSecondary: {}
            )
        case 1:
            return StepData(
                icon: "📁",
                title: "Full Disk Access",
                body: "AppX Manager reads your Applications folder, Homebrew and package-manager manifests, and app receipts to find installed versions. It never reads your documents, and nothing ever leaves your Mac.",
                note: "You'll be taken to System Settings → Privacy & Security → Full Disk Access.",
                primaryLabel: "Open System Settings",
                onPrimary: { self.openFullDiskAccessSettings() },
                secondaryLabel: "I've granted access",
                onSecondary: { self.step = 2 }
            )
        default:
            return StepData(
                icon: "✓",
                title: "You approve every update",
                body: "AppX Manager never updates anything on its own. When you click Update, it runs brew, npm, pip, gem, or mas right then — one command, one app, fully visible in the dashboard.",
                note: "No background installs, no silent changes.",
                primaryLabel: "Finish setup",
                onPrimary: onComplete,
                secondaryLabel: nil,
                onSecondary: {}
            )
        }
    }

    private func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
