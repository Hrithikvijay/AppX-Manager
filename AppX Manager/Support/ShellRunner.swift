//
//  ShellRunner.swift
//  AppX Manager
//

import Foundation

struct ShellCommandResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum ShellRunnerError: Error, LocalizedError {
    case commandNotFound(String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandNotFound(let name): "\(name) not found on PATH"
        case .launchFailed(let reason): "Failed to launch process: \(reason)"
        }
    }
}

/// Async wrapper around `Process`. Every call resolves against the user's real
/// login-shell PATH (not this GUI app's minimal default PATH), so version-manager
/// installed tools (nvm, pyenv, rbenv, etc.) are found the same way Terminal finds
/// them. Blocking `Process` calls run on a dedicated queue, never the main thread
/// or Swift's cooperative thread pool.
enum ShellRunner {
    private static let ioQueue = DispatchQueue(label: "AppXManager.ShellRunner", attributes: .concurrent)

    private static let resolvedPath: String = resolveLoginShellPath()

    private static func resolveLoginShellPath() -> String {
        let fallback = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-ilc", "echo -n \"$PATH\""]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus == 0,
               let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path + ":" + fallback
            }
        } catch {
            // Fall through to the static fallback below.
        }
        return fallback
    }

    @discardableResult
    static func run(_ executableName: String, _ arguments: [String] = []) async throws -> ShellCommandResult {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                do {
                    continuation.resume(returning: try runSync(executableName, arguments))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runSync(_ executableName: String, _ arguments: [String]) throws -> ShellCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executableName] + arguments

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = resolvedPath
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw ShellRunnerError.launchFailed(error.localizedDescription)
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus == 127 {
            throw ShellRunnerError.commandNotFound(executableName)
        }

        return ShellCommandResult(
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }
}
