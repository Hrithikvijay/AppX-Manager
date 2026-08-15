//
//  Provider.swift
//  AppX Manager
//

import Foundation

/// The concrete tool that manages an item — finer-grained than `Source`, since
/// `Source.devTools` alone doesn't say whether to shell out to npm, pip, or gem.
enum Provider: Hashable, Sendable {
    case homebrewFormula
    case homebrewCask
    case npm
    case pip
    case gem
    case appStore
    case sparkle
    case caskFallback
    case unmanaged
}
