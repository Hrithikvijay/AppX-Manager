//
//  DiskUsage.swift
//  AppX Manager
//

import Foundation

/// Best-effort disk size/creation-date lookups for install paths (Cellar dirs,
/// .app bundles, global package directories) — used to populate detail-panel info.
enum DiskUsage {
    static func size(atPath path: String) -> Int64 {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { return 0 }

        guard isDirectory.boolValue else {
            let attributes = try? fileManager.attributesOfItem(atPath: path)
            return (attributes?[.size] as? Int64) ?? 0
        }

        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    static func creationDate(atPath path: String) -> Date {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return (attributes?[.creationDate] as? Date) ?? Date()
    }
}
