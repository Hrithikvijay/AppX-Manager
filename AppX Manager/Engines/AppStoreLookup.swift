//
//  AppStoreLookup.swift
//  AppX Manager
//

import Foundation

/// Best-effort homepage discovery for direct-download apps with no Sparkle feed
/// and no Homebrew cask match, via Apple's public iTunes Search API. Name search
/// alone is unreliable (e.g. searching "Discord" returns unrelated third-party
/// wrapper apps, since the real Discord isn't on the App Store at all) — a
/// result is only trusted if its `bundleId` exactly matches the app's own real
/// bundle identifier, never by name/developer similarity alone.
enum AppStoreLookup {
    static func homepageURL(appName: String, bundleId: String) async -> URL? {
        await Task.detached(priority: .utility) {
            await fetchHomepageURL(appName: appName, bundleId: bundleId)
        }.value
    }

    private static func fetchHomepageURL(appName: String, bundleId: String) async -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: appName),
            URLQueryItem(name: "media", value: "software"),
            URLQueryItem(name: "entity", value: "macSoftware"),
            URLQueryItem(name: "limit", value: "10"),
        ]
        guard let url = components?.url else { return nil }

        guard let (data, _) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return nil
        }

        guard let match = results.first(where: { ($0["bundleId"] as? String) == bundleId }) else {
            return nil
        }

        let urlString = (match["sellerUrl"] as? String) ?? (match["trackViewUrl"] as? String)
        return urlString.flatMap(URL.init(string:))
    }
}
