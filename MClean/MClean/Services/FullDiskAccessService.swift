import AppKit
import Foundation
import Security

struct FullDiskAccessStatus: Equatable {
    let isLikelyGranted: Bool
    let checkedPaths: [String]
    let blockedPaths: [String]
}

enum FullDiskAccessService {
    static func currentStatus() -> FullDiskAccessStatus {
        // Sandboxed App Store builds cannot reliably infer Full Disk Access by probing protected folders.
        if isAppSandboxed {
            return FullDiskAccessStatus(
                isLikelyGranted: true,
                checkedPaths: [],
                blockedPaths: []
            )
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let protectedURLs = [
            home.appendingPathComponent("Library/Mail"),
            home.appendingPathComponent("Library/Messages"),
            home.appendingPathComponent("Library/Safari"),
            home.appendingPathComponent("Library/Application Support/MobileSync/Backup"),
            home.appendingPathComponent("Pictures/Photos Library.photoslibrary")
        ]

        var checked: [String] = []
        var blocked: [String] = []
        var readablePathCount = 0

        for url in protectedURLs where directoryExists(at: url) {
            checked.append(url.path)
            if (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil {
                readablePathCount += 1
            } else {
                blocked.append(url.path)
            }
        }

        return FullDiskAccessStatus(
            isLikelyGranted: checked.isEmpty || readablePathCount > 0,
            checkedPaths: checked,
            blockedPaths: blocked
        )
    }

    private static func directoryExists(at url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static var isAppSandboxed: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.security.app-sandbox" as CFString,
                nil
              ) else {
            return false
        }

        return (value as? Bool) == true
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
