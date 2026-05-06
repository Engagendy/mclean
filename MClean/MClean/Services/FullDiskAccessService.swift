import AppKit
import Foundation

struct FullDiskAccessStatus: Equatable {
    let isLikelyGranted: Bool
    let checkedPaths: [String]
    let blockedPaths: [String]
}

enum FullDiskAccessService {
    static func currentStatus() -> FullDiskAccessStatus {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let protectedURLs = [
            home.appendingPathComponent("Library/Mail"),
            home.appendingPathComponent("Library/Messages"),
            home.appendingPathComponent("Library/Safari"),
            home.appendingPathComponent("Library/Application Support/com.apple.TCC")
        ]

        var checked: [String] = []
        var blocked: [String] = []

        for url in protectedURLs where FileManager.default.fileExists(atPath: url.path) {
            checked.append(url.path)
            if (try? FileManager.default.contentsOfDirectory(atPath: url.path)) == nil {
                blocked.append(url.path)
            }
        }

        return FullDiskAccessStatus(
            isLikelyGranted: !checked.isEmpty && blocked.isEmpty,
            checkedPaths: checked,
            blockedPaths: blocked
        )
    }

    static func openSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy"
        ]

        for value in urls {
            if let url = URL(string: value), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
