//
//  NpmUpdater.swift
//  AppX Manager
//

import Foundation

enum NpmUpdater {
    static func update(_ item: InstalledItem) async throws {
        let result = try await ShellRunner.run("npm", ["update", "-g", item.name])
        guard result.exitCode == 0 else {
            throw UpdaterError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
    }
}
