//
//  InstalledItem.swift
//  AppX Manager
//

import Foundation

struct InstalledItem: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var description: String
    var source: Source
    var provider: Provider
    var developer: String
    var installedVersion: String
    var latestVersion: String?
    var status: UpdateStatus
    var sizeBytes: Int64
    var installDate: Date
    var bundleId: String
    var path: String
    var history: [VersionEntry]
    var homepageURL: URL?
    /// Only set when `provider == .caskFallback` — the matched cask token to adopt.
    var caskToken: String? = nil
}
