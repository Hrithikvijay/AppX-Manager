//
//  NpmScanner.swift
//  AppX Manager
//

import Foundation

enum NpmScanner {
    private struct ListResponse: Decodable {
        struct Dependency: Decodable {
            let version: String?
        }
        let dependencies: [String: Dependency]?
    }

    private struct OutdatedEntry: Decodable {
        let latest: String?
    }

    static private(set) var isAvailable = true

    static func scan() async -> [InstalledItem] {
        guard let listResult = try? await ShellRunner.run("npm", ["ls", "-g", "--depth=0", "--json"]),
              let data = listResult.stdout.data(using: .utf8),
              let list = try? JSONDecoder().decode(ListResponse.self, from: data) else {
            isAvailable = false
            return []
        }
        isAvailable = true

        let globalRoot = (try? await ShellRunner.run("npm", ["root", "-g"]))?.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var outdated: [String: String] = [:]
        if let outdatedResult = try? await ShellRunner.run("npm", ["outdated", "-g", "--json"]) {
            let trimmed = outdatedResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let outdatedData = trimmed.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String: OutdatedEntry].self, from: outdatedData) {
                for (name, entry) in decoded { outdated[name] = entry.latest }
            }
        }

        return (list.dependencies ?? [:]).compactMap { name, dependency -> InstalledItem? in
            guard let installed = dependency.version else { return nil }
            let latest = outdated[name]
            let path = globalRoot.isEmpty ? name : "\(globalRoot)/\(name)"
            return InstalledItem(
                id: "npm:\(name)",
                name: name,
                description: "npm global package",
                source: .devTools,
                provider: .npm,
                developer: "npm",
                installedVersion: installed,
                latestVersion: latest,
                status: latest != nil ? .updateAvailable : .upToDate,
                sizeBytes: DiskUsage.size(atPath: path),
                installDate: DiskUsage.creationDate(atPath: path),
                bundleId: "npm.global.\(name)",
                path: path,
                history: latest.map { [VersionEntry(version: $0, date: Date())] } ?? [],
                homepageURL: nil
            )
        }
    }
}
