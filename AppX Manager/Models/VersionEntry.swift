//
//  VersionEntry.swift
//  AppX Manager
//

import Foundation

struct VersionEntry: Identifiable, Hashable, Sendable {
    var id: String { version }
    let version: String
    let date: Date
}
