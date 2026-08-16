//
//  GemUpdater.swift
//  AppX Manager
//

import Foundation

enum GemUpdater {
    private static let installTimeout: TimeInterval = 900

    static func update(_ item: InstalledItem) async throws {
        let result = try await ShellRunner.run("gem", ["update", item.name], timeout: installTimeout)
        guard result.exitCode == 0 else {
            throw UpdaterError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
    }
}
