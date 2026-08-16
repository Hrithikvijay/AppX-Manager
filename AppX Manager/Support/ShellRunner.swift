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
    case timedOut(String)

    var errorDescription: String? {
        switch self {
        case .commandNotFound(let name): "\(name) not found on PATH"
        case .launchFailed(let reason): "Failed to launch process: \(reason)"
        case .timedOut(let name): "\(name) timed out"
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

    /// Default cap for any spawned process — `mas list`/`mas outdated` are known
    /// to hang indefinitely (not just error out) when not signed into the App
    /// Store. This default suits quick read-only queries (list/outdated/version
    /// checks); callers that actually install/upgrade something (which can
    /// legitimately take minutes — large downloads, compiling from source, etc.)
    /// MUST pass an explicit, much longer `timeout`.
    private static let defaultTimeout: TimeInterval = 25

    @discardableResult
    static func run(_ executableName: String, _ arguments: [String] = [], timeout: TimeInterval = defaultTimeout) async throws -> ShellCommandResult {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                do {
                    continuation.resume(returning: try runSync(executableName, arguments, timeout: timeout))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runSync(_ executableName: String, _ arguments: [String], timeout: TimeInterval) throws -> ShellCommandResult {
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

        let timeoutWorkItem = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let startTime = DispatchTime.now()
        process.waitUntilExit()
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000
        let wasTerminatedByTimeout = process.terminationReason == .uncaughtSignal
        timeoutWorkItem.cancel()

        let commandDescription = "\(executableName) \(arguments.joined(separator: " "))"
        if wasTerminatedByTimeout {
            DebugLog.log("TIMEOUT after \(String(format: "%.1f", elapsed))s: \(commandDescription)")
            throw ShellRunnerError.timedOut(executableName)
        }

        if process.terminationStatus == 127 {
            DebugLog.log("NOT FOUND: \(commandDescription)")
            throw ShellRunnerError.commandNotFound(executableName)
        }

        if process.terminationStatus != 0 {
            // Non-zero doesn't always mean "error" (e.g. `npm outdated` exits 1
            // when outdated packages exist) — callers decide what it means; this
            // just records that it happened, for diagnosing real failures later.
            let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
            DebugLog.log("exit \(process.terminationStatus) (\(String(format: "%.1f", elapsed))s): \(commandDescription)\n  stderr: \(stderrText.prefix(500))")
        } else {
            DebugLog.log("OK (\(String(format: "%.1f", elapsed))s): \(commandDescription)")
        }

        return ShellCommandResult(
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }
}
