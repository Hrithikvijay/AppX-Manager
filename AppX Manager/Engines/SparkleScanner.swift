//
//  SparkleScanner.swift
//  AppX Manager
//

import Foundation

enum SparkleScanner {
    struct DiscoveredApp {
        let name: String
        let bundleId: String
        let path: String
        let installedVersion: String
        let developer: String
    }

    /// Enumerates `/Applications/*.app`, `scan(excludingBundleIds:excludingPaths:)`
    /// then classifies each as Sparkle-managed, cask-fallback-matched, or unknown.
    static func scan(excludingBundleIds: Set<String>, excludingPaths: Set<String>) async -> [InstalledItem] {
        let apps = discoverApps(excludingBundleIds: excludingBundleIds, excludingPaths: excludingPaths)
        var items: [InstalledItem] = []
        for app in apps {
            items.append(await makeItem(for: app))
        }
        let sparkleCount = items.filter { $0.provider == .sparkle }.count
        let caskCount = items.filter { $0.provider == .caskFallback }.count
        let unknownCount = items.filter { $0.provider == .unmanaged }.count
        DebugLog.log("DIRECT-DOWNLOAD SCAN: \(items.count) apps — \(sparkleCount) sparkle, \(caskCount) cask-matched, \(unknownCount) unknown")
        return items
    }

    private static func discoverApps(excludingBundleIds: Set<String>, excludingPaths: Set<String>) -> [DiscoveredApp] {
        let applicationsURL = URL(fileURLWithPath: "/Applications")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: applicationsURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries.compactMap { url -> DiscoveredApp? in
            guard url.pathExtension == "app" else { return nil }
            let path = url.path
            guard !excludingPaths.contains(path), let bundle = Bundle(url: url),
                  let bundleId = bundle.bundleIdentifier, !excludingBundleIds.contains(bundleId) else { return nil }
            let info = bundle.infoDictionary ?? [:]
            let name = (info["CFBundleDisplayName"] as? String)
                ?? (info["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let version = (info["CFBundleShortVersionString"] as? String)
                ?? (info["CFBundleVersion"] as? String) ?? "—"
            let developer = (info["CFBundleGetInfoString"] as? String) ?? "Unknown"
            return DiscoveredApp(name: name, bundleId: bundleId, path: path, installedVersion: version, developer: developer)
        }
    }

    private static func makeItem(for app: DiscoveredApp) async -> InstalledItem {
        var latest: String?
        var provider: Provider = .unmanaged
        var caskToken: String?

        if let feedURL = feedURL(for: app.path), let feedLatest = await latestVersion(fromAppcast: feedURL) {
            latest = feedLatest
            provider = .sparkle
        } else if let match = await CaskFallbackMatcher.match(appName: app.name) {
            latest = match.latestVersion
            provider = .caskFallback
            caskToken = match.token
        }

        let status: UpdateStatus
        if provider == .unmanaged {
            status = .unknown
        } else if let latest, latest != app.installedVersion {
            status = .updateAvailable
        } else {
            status = .upToDate
        }

        return InstalledItem(
            id: "direct:\(app.bundleId)",
            name: app.name,
            description: "Downloaded directly, outside Homebrew and the App Store.",
            source: .direct,
            provider: provider,
            developer: app.developer,
            installedVersion: app.installedVersion,
            latestVersion: latest,
            status: status,
            sizeBytes: DiskUsage.size(atPath: app.path),
            installDate: DiskUsage.creationDate(atPath: app.path),
            bundleId: app.bundleId,
            path: app.path,
            history: latest.map { [VersionEntry(version: $0, date: Date())] } ?? [],
            // No standard Info.plist key reliably holds a developer homepage —
            // left nil rather than guessing; the UI hides "Visit site" when nil.
            homepageURL: nil,
            caskToken: caskToken
        )
    }

    private static func feedURL(for path: String) -> URL? {
        guard let bundle = Bundle(path: path),
              let feedString = bundle.infoDictionary?["SUFeedURL"] as? String else { return nil }
        return URL(string: feedString)
    }

    /// Fetches and parses a Sparkle appcast, returning the first (conventionally
    /// newest) `sparkle:version`/`sparkle:shortVersionString` found. Runs on an
    /// independent detached task so it isn't silently cancelled if the calling
    /// scan chain gets cancelled/restarted (see CaskFallbackMatcher.catalog()).
    private static func latestVersion(fromAppcast url: URL) async -> String? {
        await Task.detached(priority: .utility) {
            guard let (data, _) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 8)) else { return nil }
            let parser = AppcastParser()
            let xmlParser = XMLParser(data: data)
            xmlParser.delegate = parser
            guard xmlParser.parse() else { return nil }
            return parser.latestVersion
        }.value
    }

    private final class AppcastParser: NSObject, XMLParserDelegate {
        private(set) var latestVersion: String?

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            guard elementName == "enclosure", latestVersion == nil else { return }
            latestVersion = attributeDict["sparkle:version"] ?? attributeDict["sparkle:shortVersionString"]
        }
    }
}
