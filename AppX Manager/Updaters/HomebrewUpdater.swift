//
//  HomebrewUpdater.swift
//  AppX Manager
//

import Foundation

enum HomebrewUpdater {
    static func update(_ item: InstalledItem) async throws {
        let arguments: [String] = item.provider == .homebrewCask ? ["--cask", item.name] : [item.name]
        let result = try await ShellRunner.run("brew", ["upgrade"] + arguments)
        guard result.exitCode == 0 else {
            throw UpdaterError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
    }
}
