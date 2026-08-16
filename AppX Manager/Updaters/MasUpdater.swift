//
//  MasUpdater.swift
//  AppX Manager
//

import Foundation

enum MasUpdater {
    private static let installTimeout: TimeInterval = 900

    static func update(_ item: InstalledItem) async throws {
        let appId = item.id.hasPrefix("mas:") ? String(item.id.dropFirst("mas:".count)) : item.id
        let result = try await ShellRunner.run("mas", ["upgrade", appId], timeout: installTimeout)
        guard result.exitCode == 0 else {
            throw UpdaterError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
    }
}
