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

    /// Runs the fetch on an independent detached task — the calling scan chain
    /// gets re-triggered/cancelled more often than expected (still being tracked
    /// down), which was silently cancelling this ~19MB download every time and
    /// making every direct-download app show as "Unknown". A detached task has
    /// no parent/child relationship to the caller, so it isn't affected by that.
    private static func catalog() async -> [[String: Any]] {
        if let cachedCatalog { return cachedCatalog }
        let decoded = await Task.detached(priority: .utility) { await fetchCatalog() }.value
        if !decoded.isEmpty { cachedCatalog = decoded }
        return decoded
    }

    private static func fetchCatalog() async -> [[String: Any]] {
        guard let url = URL(string: "https://formulae.brew.sh/api/cask.json") else {
            DebugLog.log("CASK CATALOG: invalid URL")
            return []
        }

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 30))
        } catch {
            DebugLog.log("CASK CATALOG FETCH FAILED: \(error.localizedDescription)")
            return []
        }

        guard let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            DebugLog.log("CASK CATALOG PARSE FAILED: got \(data.count) bytes, couldn't decode as [[String: Any]]")
            return []
        }

        DebugLog.log("CASK CATALOG OK: \(decoded.count) casks, \(data.count) bytes")
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
