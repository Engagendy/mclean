import Foundation

struct ScanOptions: Equatable {
    var includeCaches = true
    var includeDownloads = true
    var includeTemporary = true
    var includeLargeFiles = true
    var includeOldFiles = true
    var includeDeveloperData = true
    var includeAppSupport = false
    var includeSystemStorage = false
    var largeFileThresholdMB = 500
    var oldFileAgeDays = 365
    var maxResults = 1_500
}

struct ScanResult {
    let items: [CleanupItem]
    let summary: ScanSummary
}

actor FileScanner {
    private let fileManager = FileManager.default

    func scan(
        options: ScanOptions,
        progress: @escaping @MainActor @Sendable (String) -> Void,
        onItem: @escaping @MainActor @Sendable (CleanupItem) -> Void,
        onSummary: @escaping @MainActor @Sendable (ScanSummary) -> Void
    ) async -> ScanResult {
        let home = fileManager.homeDirectoryForCurrentUser
        var items: [CleanupItem] = []
        var seenPaths = Set<String>()
        var summary = ScanSummary()

        if options.includeCaches {
            if Task.isCancelled { return ScanResult(items: items, summary: summary) }
            await progress("Scanning user caches")
            await collectDirectoryCandidates(
                roots: [home.appendingPathComponent("Library/Caches")],
                category: .caches,
                reason: "Application cache data",
                risk: .low,
                maxDepth: 2,
                minSize: 5 * 1_024 * 1_024,
                items: &items,
                seenPaths: &seenPaths,
                summary: &summary,
                onItem: onItem,
                onSummary: onSummary
            )
        }

        if options.includeTemporary {
            if Task.isCancelled { return ScanResult(items: items, summary: summary) }
            await progress("Scanning temporary folders")
            await collectDirectoryCandidates(
                roots: [
                    URL(fileURLWithPath: NSTemporaryDirectory()),
                    home.appendingPathComponent("Library/Logs"),
                    home.appendingPathComponent("Library/Saved Application State")
                ],
                category: .temporary,
                reason: "Temporary or log data",
                risk: .low,
                maxDepth: 2,
                minSize: 5 * 1_024 * 1_024,
                items: &items,
                seenPaths: &seenPaths,
                summary: &summary,
                onItem: onItem,
                onSummary: onSummary
            )
        }

        if options.includeDownloads {
            if Task.isCancelled { return ScanResult(items: items, summary: summary) }
            await progress("Scanning Downloads")
            await collectFileCandidates(
                roots: [home.appendingPathComponent("Downloads")],
                category: .downloads,
                reason: "Downloaded file",
                risk: .medium,
                minSize: 20 * 1_024 * 1_024,
                olderThanDays: 30,
                items: &items,
                seenPaths: &seenPaths,
                summary: &summary,
                onItem: onItem,
                onSummary: onSummary
            )
        }

        if options.includeLargeFiles {
            if Task.isCancelled { return ScanResult(items: items, summary: summary) }
            await progress("Finding large files")
            await collectFileCandidates(
                roots: [home],
                category: .largeFiles,
                reason: "Large file",
                risk: .medium,
                minSize: Int64(options.largeFileThresholdMB) * 1_024 * 1_024,
                olderThanDays: nil,
                items: &items,
                seenPaths: &seenPaths,
                summary: &summary,
                onItem: onItem,
                onSummary: onSummary
            )
        }

        if options.includeDeveloperData {
            if Task.isCancelled { return ScanResult(items: items, summary: summary) }
            await progress("Scanning developer data")
            await collectExactDirectoryCandidates(
                roots: developerDataRoots(home: home),
                category: .developerData,
                reason: "Developer build, simulator, package, or tool cache data",
                risk: .medium,
                maxDepth: 4,
                minSize: 50 * 1_024 * 1_024,
                items: &items,
                seenPaths: &seenPaths,
                summary: &summary,
                onItem: onItem,
                onSummary: onSummary
            )
        }

        if options.includeAppSupport {
            if Task.isCancelled { return ScanResult(items: items, summary: summary) }
            await progress("Scanning app support data")
            await collectDirectoryCandidates(
                roots: appSupportRoots(home: home),
                category: .appSupport,
                reason: "Large application support or container data",
                risk: .high,
                maxDepth: 3,
                minSize: 100 * 1_024 * 1_024,
                items: &items,
                seenPaths: &seenPaths,
                summary: &summary,
                onItem: onItem,
                onSummary: onSummary
            )
        }

        if options.includeSystemStorage {
            if Task.isCancelled { return ScanResult(items: items, summary: summary) }
            await progress("Scanning system storage")
            await collectExactDirectoryCandidates(
                roots: systemStorageRoots(home: home),
                category: .systemStorage,
                reason: "Large protected user-library storage",
                risk: .high,
                maxDepth: 3,
                minSize: 100 * 1_024 * 1_024,
                items: &items,
                seenPaths: &seenPaths,
                summary: &summary,
                onItem: onItem,
                onSummary: onSummary
            )
        }

        if options.includeOldFiles {
            if Task.isCancelled { return ScanResult(items: items, summary: summary) }
            await progress("Finding old files")
            await collectFileCandidates(
                roots: [home.appendingPathComponent("Documents"), home.appendingPathComponent("Desktop")],
                category: .oldFiles,
                reason: "Not modified recently",
                risk: .high,
                minSize: 50 * 1_024 * 1_024,
                olderThanDays: options.oldFileAgeDays,
                items: &items,
                seenPaths: &seenPaths,
                summary: &summary,
                onItem: onItem,
                onSummary: onSummary
            )
        }

        let sorted = items
            .sorted {
                if $0.risk.sortRank != $1.risk.sortRank { return $0.risk.sortRank < $1.risk.sortRank }
                return $0.size > $1.size
            }
            .prefix(options.maxResults)

        let finalItems = Array(sorted)
        summary.reclaimableBytes = finalItems.reduce(0) { $0 + $1.size }
        await onSummary(summary)
        return ScanResult(items: finalItems, summary: summary)
    }

    private func collectDirectoryCandidates(
        roots: [URL],
        category: CleanupCategory,
        reason: String,
        risk: CleanupRisk,
        maxDepth: Int,
        minSize: Int64,
        items: inout [CleanupItem],
        seenPaths: inout Set<String>,
        summary: inout ScanSummary,
        onItem: @escaping @MainActor @Sendable (CleanupItem) -> Void,
        onSummary: @escaping @MainActor @Sendable (ScanSummary) -> Void
    ) async {
        for root in roots where fileManager.fileExists(atPath: root.path) {
            if Task.isCancelled { return }
            guard let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .totalFileAllocatedSizeKey],
                options: [.skipsHiddenFiles]
            ) else {
                summary.skippedItems += 1
                continue
            }

            for child in children {
                if Task.isCancelled { return }
                guard !isSystemCritical(child), seenPaths.insert(child.path).inserted else { continue }
                let size = directorySize(child, maxDepth: maxDepth, summary: &summary)
                guard size >= minSize else { continue }
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
                let item = CleanupItem(
                    url: child,
                    name: child.lastPathComponent,
                    size: size,
                    modifiedAt: values?.contentModificationDate,
                    category: category,
                    risk: risk,
                    reason: reason,
                    isDirectory: values?.isDirectory ?? true
                )
                items.append(item)
                await onItem(item)
                await onSummary(summary)
            }
        }
    }

    private func collectExactDirectoryCandidates(
        roots: [URL],
        category: CleanupCategory,
        reason: String,
        risk: CleanupRisk,
        maxDepth: Int,
        minSize: Int64,
        items: inout [CleanupItem],
        seenPaths: inout Set<String>,
        summary: inout ScanSummary,
        onItem: @escaping @MainActor @Sendable (CleanupItem) -> Void,
        onSummary: @escaping @MainActor @Sendable (ScanSummary) -> Void
    ) async {
        for root in roots where fileManager.fileExists(atPath: root.path) {
            if Task.isCancelled { return }
            guard !isSystemCritical(root), seenPaths.insert(root.path).inserted else { continue }
            let values = try? root.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            guard values?.isDirectory == true else { continue }

            let beforeSkipped = summary.skippedItems
            let size = directorySize(root, maxDepth: maxDepth, summary: &summary)
            if summary.skippedItems > beforeSkipped {
                summary.protectedLocationsBlocked += 1
            }
            guard size >= minSize else { continue }

            let item = CleanupItem(
                url: root,
                name: root.lastPathComponent,
                size: size,
                modifiedAt: values?.contentModificationDate,
                category: category,
                risk: risk,
                reason: reason,
                isDirectory: true
            )
            items.append(item)
            await onItem(item)
            await onSummary(summary)
        }
    }

    private func collectFileCandidates(
        roots: [URL],
        category: CleanupCategory,
        reason: String,
        risk: CleanupRisk,
        minSize: Int64,
        olderThanDays: Int?,
        items: inout [CleanupItem],
        seenPaths: inout Set<String>,
        summary: inout ScanSummary,
        onItem: @escaping @MainActor @Sendable (CleanupItem) -> Void,
        onSummary: @escaping @MainActor @Sendable (ScanSummary) -> Void
    ) async {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]
        let cutoff = olderThanDays.map { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) ?? Date.distantPast }

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else {
                summary.skippedItems += 1
                continue
            }

            while let nextURL = enumerator.nextObject() as? URL {
                if Task.isCancelled { return }
                let url = nextURL
                if isExcludedFromDeepScan(url) {
                    enumerator.skipDescendants()
                    continue
                }

                guard !isSystemCritical(url) else { continue }
                guard let values = try? url.resourceValues(forKeys: Set(keys)) else {
                    summary.skippedItems += 1
                    continue
                }

                if values.isDirectory == true { continue }
                guard values.isRegularFile == true else { continue }

                summary.scannedFiles += 1
                if summary.scannedFiles.isMultiple(of: 500) {
                    await onSummary(summary)
                }
                let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                guard size >= minSize else { continue }

                if let cutoff, let modified = values.contentModificationDate, modified > cutoff {
                    continue
                }

                guard seenPaths.insert(url.path).inserted else { continue }
                let item = CleanupItem(
                    url: url,
                    name: url.lastPathComponent,
                    size: size,
                    modifiedAt: values.contentModificationDate,
                    category: category,
                    risk: risk,
                    reason: reason,
                    isDirectory: false
                )
                items.append(item)
                await onItem(item)
                await onSummary(summary)
            }
        }
    }

    private func directorySize(_ url: URL, maxDepth: Int, summary: inout ScanSummary) -> Int64 {
        guard maxDepth >= 0 else { return 0 }
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        guard let children = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            summary.skippedItems += 1
            return 0
        }

        var total: Int64 = 0
        for child in children where !isSystemCritical(child) {
            guard let values = try? child.resourceValues(forKeys: Set(keys)) else {
                summary.skippedItems += 1
                continue
            }
            if values.isDirectory == true {
                total += directorySize(child, maxDepth: maxDepth - 1, summary: &summary)
            } else {
                total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                summary.scannedFiles += 1
            }
        }
        return total
    }

    private func isExcludedFromDeepScan(_ url: URL) -> Bool {
        let path = url.path
        let excludedFragments = [
            "/Library/",
            "/System/",
            "/Applications/",
            "/.Trash/",
            "/Library/Mail/",
            "/Library/Photos/",
            "/Library/Messages/",
            "/Library/Application Support/MobileSync/"
        ]
        return excludedFragments.contains { path.contains($0) }
    }

    private func isSystemCritical(_ url: URL) -> Bool {
        let path = url.path
        return path == "/" ||
            path.hasPrefix("/System") ||
            path.hasPrefix("/bin") ||
            path.hasPrefix("/sbin") ||
            path.hasPrefix("/usr") ||
            path.hasPrefix("/private/var/db") ||
            path.contains("/.git/")
    }

    private func developerDataRoots(home: URL) -> [URL] {
        [
            home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
            home.appendingPathComponent("Library/Developer/Xcode/Archives"),
            home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport"),
            home.appendingPathComponent("Library/Developer/CoreSimulator/Devices"),
            home.appendingPathComponent("Library/Caches/org.swift.swiftpm"),
            home.appendingPathComponent("Library/Caches/Homebrew"),
            home.appendingPathComponent(".npm"),
            home.appendingPathComponent(".cache/yarn"),
            home.appendingPathComponent("Library/Caches/Yarn"),
            home.appendingPathComponent(".pnpm-store"),
            home.appendingPathComponent("Library/pnpm/store"),
            home.appendingPathComponent(".gradle/caches"),
            home.appendingPathComponent(".m2/repository"),
            home.appendingPathComponent("Library/Containers/com.docker.docker"),
            home.appendingPathComponent("Library/Group Containers/group.com.docker")
        ]
    }

    private func appSupportRoots(home: URL) -> [URL] {
        [
            home.appendingPathComponent("Library/Application Support"),
            home.appendingPathComponent("Library/Containers"),
            home.appendingPathComponent("Library/Group Containers"),
            home.appendingPathComponent("Library/WebKit"),
            home.appendingPathComponent("Library/HTTPStorages")
        ]
    }

    private func systemStorageRoots(home: URL) -> [URL] {
        [
            home.appendingPathComponent("Library/Application Support/MobileSync/Backup"),
            home.appendingPathComponent("Library/Mail"),
            home.appendingPathComponent("Library/Messages"),
            home.appendingPathComponent("Library/Safari"),
            home.appendingPathComponent("Library/Photos"),
            home.appendingPathComponent("Pictures/Photos Library.photoslibrary"),
            home.appendingPathComponent("Library/CloudStorage")
        ]
    }
}
