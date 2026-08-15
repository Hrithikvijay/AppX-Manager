//
//  UpdateStatus.swift
//  AppX Manager
//

import Foundation

enum UpdateStatus: Hashable, Sendable {
    case upToDate
    case updateAvailable
    case unknown
    case updating
    case failed
}
