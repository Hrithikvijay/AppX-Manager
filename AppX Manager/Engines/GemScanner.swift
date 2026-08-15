//
//  GemScanner.swift
//  AppX Manager
//

import Foundation

enum GemScanner {
    static private(set) var isAvailable = true

    static func scan() async -> [InstalledItem] {
        guard let listResult = try? await ShellRunner.run("gem", ["list"]), listResult.exitCode == 0 else {
            isAvailable = false
            return []
        }
        isAvailable = true

        let installed = parseList(listResult.stdout)

        var outdated: [String: String] = [:]
        if let outdatedResult = try? await ShellRunner.run("gem", ["outdated"]) {
            outdated = parseOutdated(outdatedResult.stdout)
        }

        let gemDir = (try? await ShellRunner.run("gem", ["environment", "gemdir"]))?.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return installed.map { name, version in
            let latest = outdated[name]
            let path = gemDir.isEmpty ? name : "\(gemDir)/gems/\(name)-\(version)"
            return InstalledItem(
                id: "gem:\(name)",
                name: name,
                description: "gem global package",
                source: .devTools,
                provider: .gem,
                developer: "gem",
                installedVersion: version,
                latestVersion: latest,
                status: latest != nil ? .updateAvailable : .upToDate,
                sizeBytes: DiskUsage.size(atPath: path),
                installDate: DiskUsage.creationDate(atPath: path),
                bundleId: "gem.global.\(name)",
                path: path,
                history: latest.map { [VersionEntry(version: $0, date: Date())] } ?? [],
                homepageURL: nil
            )
        }
    }

    /// `gem list` lines look like `name (1.2.3)`, `name (default: 1.2.3)`, or
    /// `name (1.2.3, 1.1.0)` for side-by-side installs. Default (Ruby-stdlib-bundled)
    /// gems are excluded since the user never explicitly installed them.
    static func parseList(_ output: String) -> [(String, String)] {
        output.split(separator: "\n").compactMap { substring -> (String, String)? in
            let line = String(substring)
            guard let openParen = line.firstIndex(of: "("), let closeParen = line.firstIndex(of: ")") else { return nil }
            let name = String(line[line.startIndex..<openParen]).trimmingCharacters(in: .whitespaces)
            var versionText = String(line[line.index(after: openParen)..<closeParen]).trimmingCharacters(in: .whitespaces)
            if versionText.hasPrefix("default:") { return nil }
            if let comma = versionText.firstIndex(of: ",") {
                versionText = String(versionText[versionText.startIndex..<comma]).trimmingCharacters(in: .whitespaces)
            }
            return (name, versionText)
        }
    }

    /// `gem outdated` lines look like `name (1.2.3 < 2.0.0)`.
    static func parseOutdated(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        for substring in output.split(separator: "\n") {
            let line = String(substring)
            guard let openParen = line.firstIndex(of: "("), let closeParen = line.firstIndex(of: ")"),
                  let ltSign = line.firstIndex(of: "<") else { continue }
            let name = String(line[line.startIndex..<openParen]).trimmingCharacters(in: .whitespaces)
            let latest = String(line[line.index(after: ltSign)..<closeParen]).trimmingCharacters(in: .whitespaces)
            result[name] = latest
        }
        return result
    }
}
