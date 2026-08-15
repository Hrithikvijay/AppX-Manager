//
//  PipScanner.swift
//  AppX Manager
//

import Foundation

enum PipScanner {
    private struct Package: Decodable {
        let name: String
        let version: String
    }

    private struct OutdatedPackage: Decodable {
        let name: String
        let latestVersion: String

        enum CodingKeys: String, CodingKey {
            case name
            case latestVersion = "latest_version"
        }
    }

    static private(set) var isAvailable = true

    /// PATH-resolved `pip3`, falling back to `python3 -m pip` — respects whatever
    /// pyenv/Homebrew/system Python the user's shell would actually run.
    private static func run(_ arguments: [String]) async throws -> ShellCommandResult {
        if let result = try? await ShellRunner.run("pip3", arguments) {
            return result
        }
        return try await ShellRunner.run("python3", ["-m", "pip"] + arguments)
    }

    static func scan() async -> [InstalledItem] {
        guard let listResult = try? await run(["list", "--format=json"]),
              let data = listResult.stdout.data(using: .utf8),
              let packages = try? JSONDecoder().decode([Package].self, from: data) else {
            isAvailable = false
            return []
        }
        isAvailable = true

        var outdated: [String: String] = [:]
        if let outdatedResult = try? await run(["list", "--outdated", "--format=json"]),
           let outdatedData = outdatedResult.stdout.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([OutdatedPackage].self, from: outdatedData) {
            for entry in decoded { outdated[entry.name] = entry.latestVersion }
        }

        let sitePackagesRoot = await resolveSitePackagesRoot()

        return packages.map { package in
            let latest = outdated[package.name]
            let path = sitePackagesRoot.map { "\($0)/\(package.name)" } ?? package.name
            return InstalledItem(
                id: "pip:\(package.name)",
                name: package.name,
                description: "pip global package",
                source: .devTools,
                provider: .pip,
                developer: "pip",
                installedVersion: package.version,
                latestVersion: latest,
                status: latest != nil ? .updateAvailable : .upToDate,
                sizeBytes: DiskUsage.size(atPath: path),
                installDate: DiskUsage.creationDate(atPath: path),
                bundleId: "pip.global.\(package.name)",
                path: path,
                history: latest.map { [VersionEntry(version: $0, date: Date())] } ?? [],
                homepageURL: nil
            )
        }
    }

    /// Parses `pip --version`'s `"pip X from <site-packages>/pip (python 3.x)"` to
    /// avoid an extra `pip show` call per package.
    private static func resolveSitePackagesRoot() async -> String? {
        guard let versionResult = try? await run(["--version"]),
              let fromRange = versionResult.stdout.range(of: "from "),
              let openParenRange = versionResult.stdout.range(of: " (python") else { return nil }
        let fullPath = String(versionResult.stdout[fromRange.upperBound..<openParenRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (fullPath as NSString).deletingLastPathComponent
    }
}
