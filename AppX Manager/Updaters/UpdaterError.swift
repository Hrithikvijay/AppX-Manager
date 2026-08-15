//
//  UpdaterError.swift
//  AppX Manager
//

import Foundation

enum UpdaterError: Error, LocalizedError {
    case commandFailed(String)
    case unsupported

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message): message.isEmpty ? "The update command failed." : message
        case .unsupported: "This item can't be updated automatically."
        }
    }
}
