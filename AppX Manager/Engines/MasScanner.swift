//
//  MasScanner.swift
//  AppX Manager
//

import Foundation

/// App Store apps are detected primarily via each app's own install receipt
/// (`Contents/_MASReceipt/receipt`) — this works with zero external dependencies,
/// unlike shelling out to `mas`. The `mas` CLI (if installed) is used ADDITIONALLY
/// to check for available updates; `mas` relies on undocumented App Store
/// internals and can break after macOS updates, so every `mas` call degrades
/// gracefully rather than throwing out into the shared scan.
enum MasScanner {
    /// Whether `mas` is available for update-checking — independent of whether
    /// any App Store apps were found via receipts.
    static private(set) var isMasCLIAvailable = true

    static func scan() async -> [InstalledItem] {
        let apps = discoverReceiptApps()

        var outdated: [String: String] = [:]
        if let outdatedResult = try? await ShellRunner.run("mas", ["outdated"]), outdatedResult.exitCode == 0 {
            isMasCLIAvailable = true
            outdated = parseOutdated(outdatedResult.stdout)
        } else {
            isMasCLIAvailable = false
        }

        return apps.map { app in
            let latest = outdated[app.name]
            let status: UpdateStatus = latest != nil ? .updateAvailable : (isMasCLIAvailable ? .upToDate : .unknown)
            return InstalledItem(
                id: "mas:\(app.bundleId)",
                name: app.name,
                description: isMasCLIAvailable ? "Mac App Store app" : "Mac App Store app · install mas to check for updates",
                source: .appStore,
                provider: .appStore,
                developer: "App Store",
                installedVersion: app.installedVersion,
                latestVersion: latest,
                status: status,
                sizeBytes: DiskUsage.size(atPath: app.path),
                installDate: DiskUsage.creationDate(atPath: app.path),
                bundleId: app.bundleId,
                path: app.path,
                history: latest.map { [VersionEntry(version: $0, date: Date())] } ?? [],
                homepageURL: nil
            )
        }
    }

    /// Installs `mas` via Homebrew — an explicit, user-triggered action, never automatic.
    static func installCLI() async throws {
        let result = try await ShellRunner.run("brew", ["install", "mas"], timeout: 300)
        guard result.exitCode == 0 else {
            throw UpdaterError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        isMasCLIAvailable = true
    }

    private struct ReceiptApp {
        let name: String
        let bundleId: String
        let path: String
        let installedVersion: String
    }

    private static func discoverReceiptApps() -> [ReceiptApp] {
        let applicationsURL = URL(fileURLWithPath: "/Applications")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: applicationsURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries.compactMap { url -> ReceiptApp? in
            guard url.pathExtension == "app" else { return nil }
            let receiptPath = url.appendingPathComponent("Contents/_MASReceipt/receipt").path
            guard FileManager.default.fileExists(atPath: receiptPath),
                  let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier else { return nil }
            let info = bundle.infoDictionary ?? [:]
            let name = (info["CFBundleDisplayName"] as? String)
                ?? (info["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let version = (info["CFBundleShortVersionString"] as? String)
                ?? (info["CFBundleVersion"] as? String) ?? "—"
            return ReceiptApp(name: name, bundleId: bundleId, path: url.path, installedVersion: version)
        }
    }

    /// `mas outdated` lines look like `<id> AppName (installed -> latest)`.
    private static func parseOutdated(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        for substring in output.split(separator: "\n") {
            let line = String(substring)
            guard let firstSpace = line.firstIndex(of: " "),
                  let openParen = line.lastIndex(of: "("), let closeParen = line.lastIndex(of: ")"),
                  let arrow = line.range(of: "->") else { continue }
            let name = String(line[line.index(after: firstSpace)..<openParen]).trimmingCharacters(in: .whitespaces)
            let latest = String(line[arrow.upperBound..<closeParen]).trimmingCharacters(in: .whitespaces)
            result[name] = latest
        }
        return result
    }
}
