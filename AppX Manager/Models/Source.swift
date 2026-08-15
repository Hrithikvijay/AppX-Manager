//
//  Source.swift
//  AppX Manager
//

import Foundation

enum Source: String, CaseIterable, Hashable, Sendable {
    case appStore = "App Store"
    case homebrew = "Homebrew"
    case direct = "Direct download"
    case devTools = "Dev tools"
}
