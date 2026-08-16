//
//  HomebrewUpdater.swift
//  AppX Manager
//

import Foundation

enum HomebrewUpdater {
    /// Installs/compiles can legitimately take minutes — far longer than
    /// ShellRunner's default query timeout.
    private static let installTimeout: TimeInterval = 900

    static func update(_ item: InstalledItem) async throws {
        let arguments: [String] = item.provider == .homebrewCask ? ["--cask", item.name] : [item.name]
        let result = try await ShellRunner.run("brew", ["upgrade"] + arguments, timeout: installTimeout)
        guard result.exitCode == 0 else {
            throw UpdaterError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
    }
}
