//
//  MasScanner.swift
//  AppX Manager
//

import Foundation

/// `mas` relies on undocumented App Store internals and can break after macOS
/// updates (or simply not be installed) — every call here degrades to an empty,
/// non-fatal result rather than throwing out into the shared scan.
enum MasScanner {
    static private(set) var isAvailable = true

    static func scan() async -> [InstalledItem] {
        guard let listResult = try? await ShellRunner.run("mas", ["list"]), listResult.exitCode == 0 else {
            isAvailable = false
            return []
        }
        isAvailable = true

        let outdated = (try? await ShellRunner.run("mas", ["outdated"])).map { parseOutdated($0.stdout) } ?? [:]

        var items: [InstalledItem] = []
        for substring in listResult.stdout.split(separator: "\n") {
            let line = String(substring)
            guard let firstSpace = line.firstIndex(of: " "),
                  let openParen = line.lastIndex(of: "("), let closeParen = line.lastIndex(of: ")") else { continue }
            let id = String(line[line.startIndex..<firstSpace])
            let name = String(line[line.index(after: firstSpace)..<openParen]).trimmingCharacters(in: .whitespaces)
            let installedVersion = String(line[line.index(after: openParen)..<closeParen]).trimmingCharacters(in: .whitespaces)
            let latest = outdated[id]
            let path = "/Applications/\(name).app"
            items.append(InstalledItem(
                id: "mas:\(id)",
                name: name,
                description: "Mac App Store app",
                source: .appStore,
                provider: .appStore,
                developer: "App Store",
                installedVersion: installedVersion,
                latestVersion: latest,
                status: latest != nil ? .updateAvailable : .upToDate,
                sizeBytes: DiskUsage.size(atPath: path),
                installDate: DiskUsage.creationDate(atPath: path),
                bundleId: Bundle(path: path)?.bundleIdentifier ?? "mas.\(id)",
                path: path,
                history: latest.map { [VersionEntry(version: $0, date: Date())] } ?? [],
                homepageURL: nil
            ))
        }
        return items
    }

    /// `mas outdated` lines look like `<id> AppName (installed -> latest)`.
    private static func parseOutdated(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        for substring in output.split(separator: "\n") {
            let line = String(substring)
            guard let firstSpace = line.firstIndex(of: " "),
                  let openParen = line.lastIndex(of: "("), let closeParen = line.lastIndex(of: ")"),
                  let arrow = line.range(of: "->") else { continue }
            let id = String(line[line.startIndex..<firstSpace])
            let versions = String(line[line.index(after: openParen)..<closeParen])
            let latest = String(versions[arrow.upperBound...]).trimmingCharacters(in: .whitespaces)
            result[id] = latest
        }
        return result
    }
}
