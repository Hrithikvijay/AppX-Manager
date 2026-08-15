//
//  MasUpdater.swift
//  AppX Manager
//

import Foundation

enum MasUpdater {
    static func update(_ item: InstalledItem) async throws {
        let appId = item.id.hasPrefix("mas:") ? String(item.id.dropFirst("mas:".count)) : item.id
        let result = try await ShellRunner.run("mas", ["upgrade", appId])
        guard result.exitCode == 0 else {
            throw UpdaterError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
    }
}
