//
//  CaskFallbackMatcher.swift
//  AppX Manager
//

import Foundation

/// Best-effort match of a `/Applications` app with no Sparkle feed against
/// Homebrew's public cask catalog, by app/artifact name (not bundle id — the
/// public cask API doesn't reliably expose one for reverse lookup).
enum CaskFallbackMatcher {
    struct Match {
        let token: String
        let latestVersion: String
    }

    private static var cachedCatalog: [[String: Any]]?

    private static func catalog() async -> [[String: Any]] {
        if let cachedCatalog { return cachedCatalog }
        guard let url = URL(string: "https://formulae.brew.sh/api/cask.json"),
              let (data, _) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 15)),
              let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        cachedCatalog = decoded
        return decoded
    }

    /// Matches by exact (case-insensitive) app-bundle filename in a cask's
    /// `artifacts: [{app: [...]}]` list, or by the cask's display name.
    static func match(appName: String) async -> Match? {
        let target = appName.lowercased()
        let targetAppFile = "\(target).app"
        for entry in await catalog() {
            guard let token = entry["token"] as? String, let rawVersion = entry["version"] as? String else { continue }
            let version = primaryVersion(rawVersion)
            if let names = entry["name"] as? [String], names.contains(where: { $0.lowercased() == target }) {
                return Match(token: token, latestVersion: version)
            }
            if let artifacts = entry["artifacts"] as? [[String: Any]] {
                for artifact in artifacts {
                    if let apps = artifact["app"] as? [String], apps.contains(where: { $0.lowercased() == targetAppFile }) {
                        return Match(token: token, latestVersion: version)
                    }
                }
            }
        }
        return nil
    }

    /// Cask versions are sometimes `"1.2.3,buildid"` — only the part before the
    /// comma is the human-meaningful version.
    private static func primaryVersion(_ raw: String) -> String {
        guard let comma = raw.firstIndex(of: ",") else { return raw }
        return String(raw[raw.startIndex..<comma])
    }
}
