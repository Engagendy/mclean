import Foundation

/// Maps an installed application bundle to the on-disk data it owns
/// (caches, containers, preferences, logs, launch agents, receipts).
enum AppUninstallInspector {
    struct InspectedApp: Equatable {
        let name: String
        let bundleID: String
        let appURL: URL
        let items: [CleanupItem]

        var totalBytes: Int64 { items.reduce(0) { $0 + $1.size } }
    }

    static func inspect(appAt appURL: URL) -> InspectedApp? {
        guard appURL.pathExtension == "app",
              let bundle = Bundle(url: appURL),
              let bundleID = bundle.bundleIdentifier else {
            return nil
        }

        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let appName = appURL.deletingPathExtension().lastPathComponent
        var items: [CleanupItem] = []
        var seenPaths = Set<String>()

        func appendIfPresent(_ url: URL, reason: String, risk: CleanupRisk = .medium) {
            let path = url.standardizedFileURL.path
            guard seenPaths.insert(path).inserted, fileManager.fileExists(atPath: path) else { return }
            var isDirectory = ObjCBool(false)
            fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            items.append(CleanupItem(
                url: url,
                name: url.lastPathComponent,
                size: totalSize(of: url),
                modifiedAt: values?.contentModificationDate,
                category: .appLeftovers,
                risk: risk,
                reason: reason,
                isDirectory: isDirectory.boolValue,
                protection: .reviewOnly,
                relatedBundleID: bundleID,
                sourceKind: .appLeftover,
                sourceName: bundleID,
                sourceWarning: "Data belonging to \(appName). Review before removing."
            ))
        }

        appendIfPresent(appURL, reason: "Application bundle", risk: .high)

        let exactLocations: [(URL, String)] = [
            (home.appendingPathComponent("Library/Caches/\(bundleID)"), "Cache data"),
            (home.appendingPathComponent("Library/Application Support/\(bundleID)"), "Application support data"),
            (home.appendingPathComponent("Library/Application Support/\(appName)"), "Application support data"),
            (home.appendingPathComponent("Library/Containers/\(bundleID)"), "Sandbox container"),
            (home.appendingPathComponent("Library/HTTPStorages/\(bundleID)"), "HTTP storage"),
            (home.appendingPathComponent("Library/WebKit/\(bundleID)"), "WebKit data"),
            (home.appendingPathComponent("Library/Preferences/\(bundleID).plist"), "Preferences"),
            (home.appendingPathComponent("Library/Logs/\(bundleID)"), "Logs"),
            (home.appendingPathComponent("Library/Logs/\(appName)"), "Logs"),
            (home.appendingPathComponent("Library/Saved Application State/\(bundleID).savedState"), "Saved window state"),
            (home.appendingPathComponent("Library/Caches/\(appName)"), "Cache data")
        ]
        for (url, reason) in exactLocations {
            appendIfPresent(url, reason: reason)
        }

        let prefixSearchRoots = [
            home.appendingPathComponent("Library/Group Containers"),
            home.appendingPathComponent("Library/LaunchAgents"),
            URL(fileURLWithPath: "/Library/LaunchAgents"),
            URL(fileURLWithPath: "/Library/LaunchDaemons"),
            URL(fileURLWithPath: "/private/var/db/receipts")
        ]
        for root in prefixSearchRoots {
            guard let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for child in children where child.lastPathComponent.localizedCaseInsensitiveContains(bundleID) {
                appendIfPresent(child, reason: relatedFileReason(for: root))
            }
        }

        return InspectedApp(
            name: appName,
            bundleID: bundleID,
            appURL: appURL,
            items: items.sorted { $0.size > $1.size }
        )
    }

    private static func relatedFileReason(for root: URL) -> String {
        let path = root.path
        if path.contains("Group Containers") { return "Group container" }
        if path.contains("LaunchAgents") { return "Launch agent" }
        if path.contains("LaunchDaemons") { return "Launch daemon" }
        if path.contains("receipts") { return "Install receipt" }
        return "Related data"
    }

    private static func totalSize(of url: URL) -> Int64 {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }

        if !isDirectory.boolValue {
            let values = try? url.resourceValues(forKeys: Set(keys))
            return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        while let child = enumerator.nextObject() as? URL {
            guard let values = try? child.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }
}
