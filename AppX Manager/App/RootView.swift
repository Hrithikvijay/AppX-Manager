//
//  RootView.swift
//  AppX Manager
//

import SwiftUI

enum AppScreen {
    case onboarding
    case scanning
    case dashboard
}

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var screen: AppScreen = .onboarding
    @State private var scanEngine = ScanEngine()

    var body: some View {
        Group {
            switch screen {
            case .onboarding:
                OnboardingView(onComplete: {
                    hasCompletedOnboarding = true
                    screen = .scanning
                })
            case .scanning:
                ScanningView(scanEngine: scanEngine)
            case .dashboard:
                DashboardView(scanEngine: scanEngine, onRescan: { screen = .scanning })
            }
        }
        .onAppear {
            if hasCompletedOnboarding, scanEngine.lastScanned == nil {
                screen = .scanning
            }
        }
        .task(id: screen) {
            guard screen == .scanning else { return }
            await scanEngine.scan()
            screen = .dashboard
        }
    }
}

#Preview {
    RootView()
}
