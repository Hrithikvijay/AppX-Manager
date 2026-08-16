//
//  PipUpdater.swift
//  AppX Manager
//

import Foundation

enum PipUpdater {
    private static let installTimeout: TimeInterval = 900

    static func update(_ item: InstalledItem) async throws {
        if let result = try? await ShellRunner.run("pip3", ["install", "--upgrade", item.name], timeout: installTimeout), result.exitCode == 0 {
            return
        }
        let result = try await ShellRunner.run("python3", ["-m", "pip", "install", "--upgrade", item.name], timeout: installTimeout)
        guard result.exitCode == 0 else {
            throw UpdaterError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
    }
}
