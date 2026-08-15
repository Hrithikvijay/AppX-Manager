//
//  HomebrewScanner.swift
//  AppX Manager
//

import Foundation

enum HomebrewScanner {
    struct OutdatedResponse: Decodable {
        struct Entry: Decodable {
            let name: String
            let currentVersion: String

            enum CodingKeys: String, CodingKey {
                case name
                case currentVersion = "current_version"
            }
        }
        let formulae: [Entry]
        let casks: [Entry]
    }

    static private(set) var isAvailable = true

    static func scan() async -> [InstalledItem] {
        guard let prefixResult = try? await ShellRunner.run("brew", ["--prefix"]), prefixResult.exitCode == 0 else {
            isAvailable = false
            return []
        }
        isAvailable = true
        let prefix = prefixResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        async let formulaVersionsResult = try? ShellRunner.run("brew", ["list", "--formula", "--versions"])
        async let caskVersionsResult = try? ShellRunner.run("brew", ["list", "--cask", "--versions"])
        async let outdatedResult = try? ShellRunner.run("brew", ["outdated", "--json=v2"])

        var outdatedFormulae: [String: String] = [:]
        var outdatedCasks: [String: String] = [:]
        if let outdatedResult = await outdatedResult, outdatedResult.exitCode == 0,
           let data = outdatedResult.stdout.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(OutdatedResponse.self, from: data) {
            for entry in decoded.formulae { outdatedFormulae[entry.name] = entry.currentVersion }
            for entry in decoded.casks { outdatedCasks[entry.name] = entry.currentVersion }
        }

        var items: [InstalledItem] = []

        if let result = await formulaVersionsResult, result.exitCode == 0 {
            for line in result.stdout.split(separator: "\n") {
                let parts = line.split(separator: " ")
                guard let name = parts.first.map(String.init) else { continue }
                let installed = parts.count > 1 ? String(parts[1]) : "—"
                let path = "\(prefix)/Cellar/\(name)/\(installed)"
                items.append(makeItem(
                    name: name, installed: installed, latest: outdatedFormulae[name],
                    provider: .homebrewFormula, developer: "Homebrew",
                    description: "Homebrew formula", bundleId: "sh.brew.formula.\(name)", path: path
                ))
            }
        }

        if let result = await caskVersionsResult, result.exitCode == 0 {
            for line in result.stdout.split(separator: "\n") {
                let parts = line.split(separator: " ")
                guard let name = parts.first.map(String.init) else { continue }
                let installed = parts.count > 1 ? String(parts[1]) : "—"
                let resolvedPath = await resolveCaskAppPath(token: name, prefix: prefix, version: installed)
                items.append(makeItem(
                    name: name, installed: installed, latest: outdatedCasks[name],
                    provider: .homebrewCask, developer: "Homebrew Cask",
                    description: "Homebrew cask", bundleId: "sh.brew.cask.\(name)", path: resolvedPath
                ))
            }
        }

        return items
    }

    private static func makeItem(
        name: String, installed: String, latest: String?, provider: Provider,
        developer: String, description: String, bundleId: String, path: String
    ) -> InstalledItem {
        // `path` still uses the raw (possibly comma-suffixed) version — that's the
        // real Cellar/Caskroom directory name — only the displayed strings are cleaned.
        let displayInstalled = primaryVersion(installed)
        let displayLatest = latest.map(primaryVersion)
        return InstalledItem(
            id: "brew:\(provider == .homebrewCask ? "cask" : "formula"):\(name)",
            name: name,
            description: description,
            source: .homebrew,
            provider: provider,
            developer: developer,
            installedVersion: displayInstalled,
            latestVersion: displayLatest,
            status: latest != nil ? .updateAvailable : .upToDate,
            sizeBytes: DiskUsage.size(atPath: path),
            installDate: DiskUsage.creationDate(atPath: path),
            bundleId: bundleId,
            path: path,
            history: displayLatest.map { [VersionEntry(version: $0, date: Date())] } ?? [],
            homepageURL: nil
        )
    }

    /// Homebrew casks sometimes report versions as `"1.2.3,buildid"` — only the
    /// part before the comma is the human-meaningful version; the rest is internal
    /// build metadata (also used verbatim as the on-disk Caskroom directory name).
    private static func primaryVersion(_ raw: String) -> String {
        guard let comma = raw.firstIndex(of: ",") else { return raw }
        return String(raw[raw.startIndex..<comma])
    }

    /// Casks that install a GUI app resolve to `/Applications/<App>.app`; CLI-only
    /// casks (no `app` artifact) fall back to their Caskroom metadata directory.
    private static func resolveCaskAppPath(token: String, prefix: String, version: String) async -> String {
        let caskroomPath = "\(prefix)/Caskroom/\(token)/\(version)"
        guard let result = try? await ShellRunner.run("brew", ["info", "--cask", "--json=v2", token]),
              result.exitCode == 0,
              let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let casks = json["casks"] as? [[String: Any]],
              let artifacts = casks.first?["artifacts"] as? [[String: Any]] else {
            return caskroomPath
        }
        for artifact in artifacts {
            if let apps = artifact["app"] as? [String], let appName = apps.first {
                return "/Applications/\(appName)"
            }
        }
        return caskroomPath
    }
}
