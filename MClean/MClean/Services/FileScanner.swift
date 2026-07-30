import CryptoKit
import Foundation

struct ScanOptions: Equatable, Codable {
    var includeCaches = true
    var includeDownloads = true
    var includeTemporary = true
    var includeLargeFiles = true
    var includeDuplicates = true
    var includeOldFiles = true
    var includeDeveloperData = true
    var includeAppLeftovers = true
    var includeBrowserCaches = false
    var includeAppSupport = false
    var includeSystemStorage = false
    var largeFileThresholdMB = 500
    var oldFileAgeDays = 365
    var maxResults = 1_500
    var excludedPaths: [String] = []
    var customScanRoots: [String] = []

    private enum CodingKeys: String, CodingKey {
        case includeCaches
        case includeDownloads
        case includeTemporary
        case includeLargeFiles
        case includeDuplicates
        case includeOldFiles
        case includeDeveloperData
        case includeAppLeftovers
        case includeBrowserCaches
        case includeAppSupport
        case includeSystemStorage
        case largeFileThresholdMB
        case oldFileAgeDays
        case maxResults
        case excludedPaths
        case customScanRoots
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        includeCaches = try container.decodeIfPresent(Bool.self, forKey: .includeCaches) ?? true
        includeDownloads = try container.decodeIfPresent(Bool.self, forKey: .includeDownloads) ?? true
        includeTemporary = try container.decodeIfPresent(Bool.self, forKey: .includeTemporary) ?? true
        includeLargeFiles = try container.decodeIfPresent(Bool.self, forKey: .includeLargeFiles) ?? true
        includeDuplicates = try container.decodeIfPresent(Bool.self, forKey: .includeDuplicates) ?? true
        includeOldFiles = try container.decodeIfPresent(Bool.self, forKey: .includeOldFiles) ?? true
        includeDeveloperData = try container.decodeIfPresent(Bool.self, forKey: .includeDeveloperData) ?? true
        includeAppLeftovers = try container.decodeIfPresent(Bool.self, forKey: .includeAppLeftovers) ?? true
        includeBrowserCaches = try container.decodeIfPresent(Bool.self, forKey: .includeBrowserCaches) ?? false
        includeAppSupport = try container.decodeIfPresent(Bool.self, forKey: .includeAppSupport) ?? false
        includeSystemStorage = try container.decodeIfPresent(Bool.self, forKey: .includeSystemStorage) ?? false
        largeFileThresholdMB = try container.decodeIfPresent(Int.self, forKey: .largeFileThresholdMB) ?? 500
        oldFileAgeDays = try container.decodeIfPresent(Int.self, forKey: .oldFileAgeDays) ?? 365
        maxResults = try container.decodeIfPresent(Int.self, forKey: .maxResults) ?? 1_500
        excludedPaths = try container.decodeIfPresent([String].self, forKey: .excludedPaths) ?? []
        customScanRoots = try container.decodeIfPresent([String].self, forKey: .customScanRoots) ?? []
    }
}

struct ScanResult {
    let items: [CleanupItem]
    let summary: ScanSummary
}

actor FileScanner {
    private let fileManager = FileManager.default

    private struct DeveloperDataRoot {
        let url: URL
        let sourceName: String
        let warning: String?
    }

    private struct BrowserCacheRoot {
        let url: URL
        let browserName: String
        let profileName: String?
    }

    func scan(
        options: ScanOptions,
        progress: @escaping @MainActor @Sendable (ScanProgress) -> Void,
        shouldSkipPhase: @escaping @MainActor @Sendable (ScanPhase) -> Bool,
        onItem: @escaping @MainActor @Sendable (CleanupItem) -> Void,
        onSummary: @escaping @MainActor @Sendable (ScanSummary) -> Void
    ) async -> ScanResult {
        let home = fileManager.homeDirectoryForCurrentUser
        var items: [CleanupItem] = []
        var seenPaths = Set<String>()
        var summary = ScanSummary()
        let excludedPaths = normalizedExcludedPaths(options.excludedPaths)
        let customRoots = options.customScanRoots
            .map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath).standardizedFileURL }
        let phases = enabledScanPhases(for: options)
        var skippedPhases: [ScanPhase] = []

        func progressSnapshot(for phase: ScanPhase, phaseStartCount: Int) -> ScanProgress {
            ScanProgress(
                phase: phase,
                phaseIndex: (phases.firstIndex(of: phase) ?? 0) + 1,
                totalPhases: phases.count,
                phaseScannedFiles: max(summary.scannedFiles - phaseStartCount, 0),
                totalScannedFiles: summary.scannedFiles,
                skippedPhases: skippedPhases
            )
        }

        func summaryHandler(for phase: ScanPhase, phaseStartCount: Int) -> @MainActor @Sendable (ScanSummary) -> Void {
            let skippedSnapshot = skippedPhases
            return { currentSummary in
                onSummary(currentSummary)
                progress(ScanProgress(
                    phase: phase,
                    phaseIndex: (phases.firstIndex(of: phase) ?? 0) + 1,
                    totalPhases: phases.count,
                    phaseScannedFiles: max(currentSummary.scannedFiles - phaseStartCount, 0),
                    totalScannedFiles: currentSummary.scannedFiles,
                    skippedPhases: skippedSnapshot
                ))
            }
        }

        func startPhase(_ phase: ScanPhase) async -> Int {
            let phaseStartCount = summary.scannedFiles
            await progress(progressSnapshot(for: phase, phaseStartCount: phaseStartCount))
            return phaseStartCount
        }

        func finishPhaseIfSkipped(_ phase: ScanPhase) async {
            if await shouldSkipPhase(phase), !skippedPhases.contains(phase) {
                skippedPhases.append(phase)
                await progress(ScanProgress(
                    phase: phase,
                    phaseIndex: (phases.firstIndex(of: phase) ?? 0) + 1,
                    totalPhases: phases.count,
                    phaseScannedFiles: 0,
                    totalScannedFiles: summary.scannedFiles,
                    skippedPhases: skippedPhases
                ))
            }
        }

        func shouldStopPhase(_ phase: ScanPhase) async -> Bool {
            if Task.isCancelled { return true }
            return await shouldSkipPhase(phase)
        }

        if options.includeCaches {
            if Task.isCancelled { return ScanResult(items: items, summary: summary) }
            let phase = ScanPhase.userCaches
            let phaseStartCount = await startPhase(phase)
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
                excludedPaths: excludedPaths,
                phase: phase,
                shouldStopPhase: shouldStopPhase,
                onItem: onItem,
                onSummary: summaryHandler(for: phase, phaseStartCount: phaseStartCount)
            )
            await finishPhaseIfSkipped(phase)
        }

        if options.includeTemporary {
            if Task.isCancelled { return ScanResult(items: items, summary: summary) }
            let phase = ScanPhase.temporary
            let phaseStartCount = await startPhase(phase)
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
                excludedPaths: excludedPaths,
                phase: phase,
                shouldStopPhase: shouldStopPhase,
                onItem: onItem,
                onSummary: summaryHandler(for: phase, phaseStartCount: phaseStartCount)
            )
            await finishPhaseIfSkipped(phase)
        }

        if options.includeDownloads {
            if Task.isCancelled { return ScanResult(items: items, summary: summary) }
            let phase = ScanPhase.downloads
            let phaseStartCount = await startPhase(phase)
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
                excludedPaths: excludedPaths,
                phase: phase,
                shouldStopPhase: shouldStopPhase,
                onItem: onItem,
                onSummary: summaryHandler(for: phase, phaseStartCount: phaseStartCount)
            )
            await collectFileCandidates(
                roots: [home.appendingPathComponent("Downloads")],
                category: .downloads,
                reason: "Old installer download",
                risk: .low,
                minSize: 5 * 1_024 * 1_024,
                olderThanDays: 30,
                fileExtensions: ["dmg", "pkg", "iso", "xip"],
                items: &items,
                seenPaths: &seenPaths,
                summary: &summary,
                excludedPaths: excludedPaths,
                sourceName: "Installers",
                sourceWarning: "Installers can usually be downloaded again. Keep any you need for offline reinstalls.",
                phase: phase,
                shouldStopPhase: shouldStopPhase,
                onItem: onItem,
                onSummary: summaryHandler(for: phase, phaseStartCount: phaseStartCount)
            )
            await finishPhaseIfSkipped(phase)
        }

        if options.includeLargeFiles {
            if Task.isCancelled { return ScanResult(items: items, summary: summary) }
            let phase = ScanPhase.largeFiles
            let phaseStartCount = await startPhase(phase)
            await collectFileCandidates(
                roots: [home] + customRoots,
                category: .largeFiles,
                reason: "Large file",
                risk: .medium,
                minSize: Int64(options.largeFileThresholdMB) * 1_024 * 1_024,
                olderThanDays: nil,
                items: &items,
                seenPaths: &seenPaths,
                summary: &summary,
                excludedPaths: excludedPaths,
                phase: phase,
                shouldStopPhase: shouldStopPhase,
                onItem: onItem,
                onSummary: summaryHandler(for: phase, phaseStartCount: phaseStartCount)
            )
            await finishPhaseIfSkipped(phase)
        }

        if options.includeDeveloperData {
            if Task.isCancelled { return ScanResult(items: items, summary: summary) }
            let phase = ScanPhase.developerData
            let phaseStartCount = await startPhase(phase)
            await collectExactDirectoryCandidates(
                roots: developerDataRoots(home: home).map(\.url),
                category: .developerData,
                reason: "Developer build, simulator, package, or tool cache data",
                risk: .medium,
                maxDepth: 4,
                minSize: 50 * 1_024 * 1_024,
                items: &items,
                seenPaths: &seenPaths,
                summary: &summary,
                excludedPaths: excludedPaths,
                sourceKind: .developer,
                sourceNameProvider: { url in
                    self.developerSource(for: url, home: home)?.sourceName
                },
                sourceWarningProvider: { url in
                    self.developerSource(for: url, home: home)?.warning
                },
                phase: phase,
                shouldStopPhase: shouldStopPhase,
                onItem: onItem,
                onSummary: summaryHandler(for: phase, phaseStartCount: phaseStartCount)
            )
            await collectPythonBytecodeCandidates(
                roots: pythonProjectRoots(home: home),
                items: &items,
                seenPaths: &seenPaths,
                summary: &summary,
                excludedPaths: excludedPaths,
                phase: phase,
                shouldStopPhase: shouldStopPhase,
                onItem: onItem,
                onSummary: summaryHandler(for: phase, phaseStartCount: phaseStartCount)
            )
            await finishPhaseIfSkipped(phase)
        }

        if options.includeBrowserCaches {
            if Task.isCancelled { return ScanResult(items: items, summary: summary) }
            let phase = ScanPhase.browserCaches
            let phaseStartCount = await startPhase(phase)
            await collectBrowserCacheCandidates(
                roots: browserCacheRoots(home: home),
                items: &items,
                seenPaths: &seenPaths,
                summary: &summary,
                excludedPaths: excludedPaths,
                phase: phase,
                shouldStopPhase: shouldStopPhase,
                onItem: onItem,
                onSummary: summaryHandler(for: phase, phaseStartCount: phaseStartCount)
            )
            await finishPhaseIfSkipped(phase)
        }

        if options.includeDuplicates {
            if Task.isCancelled { return ScanResult(items: items, summary: summary) }
            let phase = ScanPhase.duplicates
            let phaseStartCount = await startPhase(phase)
            await collectDuplicateFileCandidates(
                roots: [
                    home.appendingPathComponent("Downloads"),
                    home.appendingPathComponent("Documents"),
                    home.appendingPathComponent("Desktop")
                ] + customRoots,
                minSize: 10 * 1_024 * 1_024,
                items: &items,
                seenPaths: &seenPaths,
                summary: &summary,
                excludedPaths: excludedPaths,
                phase: phase,
                shouldStopPhase: shouldStopPhase,
                onItem: onItem,
                onSummary: summaryHandler(for: phase, phaseStartCount: phaseStartCount)
            )
            await finishPhaseIfSkipped(phase)
        }

        if options.includeAppLeftovers {
            if Task.isCancelled { return ScanResult(items: items, summary: summary) }
            let phase = ScanPhase.appLeftovers
            let phaseStartCount = await startPhase(phase)
            await collectAppLeftoverCandidates(
                home: home,
                items: &items,
                seenPaths: &seenPaths,
                summary: &summary,
                excludedPaths: excludedPaths,
                phase: phase,
                shouldStopPhase: shouldStopPhase,
                onItem: onItem,
                onSummary: summaryHandler(for: phase, phaseStartCount: phaseStartCount)
            )
            await finishPhaseIfSkipped(phase)
        }

        if options.includeAppSupport {
            if Task.isCancelled { return ScanResult(items: items, summary: summary) }
            let phase = ScanPhase.appSupport
            let phaseStartCount = await startPhase(phase)
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
                excludedPaths: excludedPaths,
                phase: phase,
                shouldStopPhase: shouldStopPhase,
                onItem: onItem,
                onSummary: summaryHandler(for: phase, phaseStartCount: phaseStartCount)
            )
            await finishPhaseIfSkipped(phase)
        }

        if options.includeSystemStorage {
            if Task.isCancelled { return ScanResult(items: items, summary: summary) }
            let phase = ScanPhase.systemStorage
            let phaseStartCount = await startPhase(phase)
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
                excludedPaths: excludedPaths,
                phase: phase,
                shouldStopPhase: shouldStopPhase,
                onItem: onItem,
                onSummary: summaryHandler(for: phase, phaseStartCount: phaseStartCount)
            )
            await finishPhaseIfSkipped(phase)
        }

        if options.includeOldFiles {
            if Task.isCancelled { return ScanResult(items: items, summary: summary) }
            let phase = ScanPhase.oldFiles
            let phaseStartCount = await startPhase(phase)
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
                excludedPaths: excludedPaths,
                phase: phase,
                shouldStopPhase: shouldStopPhase,
                onItem: onItem,
                onSummary: summaryHandler(for: phase, phaseStartCount: phaseStartCount)
            )
            await finishPhaseIfSkipped(phase)
        }

        let sorted = items
            .sorted {
                if $0.protection.sortRank != $1.protection.sortRank { return $0.protection.sortRank < $1.protection.sortRank }
                if $0.risk.sortRank != $1.risk.sortRank { return $0.risk.sortRank < $1.risk.sortRank }
                return $0.size > $1.size
            }
            .prefix(options.maxResults)

        let finalItems = Array(sorted)
        summary.reclaimableBytes = finalItems.filter(\.canMoveToTrash).reduce(0) { $0 + $1.size }
        await onSummary(summary)
        return ScanResult(items: finalItems, summary: summary)
    }

    private func enabledScanPhases(for options: ScanOptions) -> [ScanPhase] {
        var phases: [ScanPhase] = []
        if options.includeCaches { phases.append(.userCaches) }
        if options.includeTemporary { phases.append(.temporary) }
        if options.includeDownloads { phases.append(.downloads) }
        if options.includeLargeFiles { phases.append(.largeFiles) }
        if options.includeDeveloperData { phases.append(.developerData) }
        if options.includeBrowserCaches { phases.append(.browserCaches) }
        if options.includeDuplicates { phases.append(.duplicates) }
        if options.includeAppLeftovers { phases.append(.appLeftovers) }
        if options.includeAppSupport { phases.append(.appSupport) }
        if options.includeSystemStorage { phases.append(.systemStorage) }
        if options.includeOldFiles { phases.append(.oldFiles) }
        return phases
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
        excludedPaths: [String],
        sourceKind: CleanupSourceKind? = nil,
        sourceName: String? = nil,
        sourceWarning: String? = nil,
        phase: ScanPhase,
        shouldStopPhase: @escaping (ScanPhase) async -> Bool,
        onItem: @escaping @MainActor @Sendable (CleanupItem) -> Void,
        onSummary: @escaping @MainActor @Sendable (ScanSummary) -> Void
    ) async {
        for root in roots where fileManager.fileExists(atPath: root.path) && !isExcluded(root, excludedPaths: excludedPaths) {
            if await shouldStopPhase(phase) { return }
            guard let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .totalFileAllocatedSizeKey],
                options: [.skipsHiddenFiles]
            ) else {
                summary.skippedItems += 1
                continue
            }

            for child in children {
                if await shouldStopPhase(phase) { return }
                guard !isExcluded(child, excludedPaths: excludedPaths) else { continue }
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
                    isDirectory: values?.isDirectory ?? true,
                    protection: protection(for: child, category: category, risk: risk),
                    sourceKind: sourceKind ?? CleanupItem.defaultSourceKind(for: category),
                    sourceName: sourceName,
                    sourceWarning: sourceWarning
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
        excludedPaths: [String],
        sourceKind: CleanupSourceKind? = nil,
        sourceNameProvider: ((URL) -> String?)? = nil,
        sourceWarningProvider: ((URL) -> String?)? = nil,
        phase: ScanPhase,
        shouldStopPhase: @escaping (ScanPhase) async -> Bool,
        onItem: @escaping @MainActor @Sendable (CleanupItem) -> Void,
        onSummary: @escaping @MainActor @Sendable (ScanSummary) -> Void
    ) async {
        for root in roots where fileManager.fileExists(atPath: root.path) && !isExcluded(root, excludedPaths: excludedPaths) {
            if await shouldStopPhase(phase) { return }
            guard !isSystemCritical(root), seenPaths.insert(root.path).inserted else { continue }
            let values = try? root.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            guard values?.isDirectory == true else { continue }

            let beforeSkipped = summary.skippedItems
            let size = directorySize(root, maxDepth: maxDepth, summary: &summary)
            if summary.skippedItems > beforeSkipped {
                summary.protectedLocationsBlocked += 1
            }
            guard size >= minSize else { continue }

            let sourceName = sourceNameProvider?(root)
            let sourceWarning = sourceWarningProvider?(root)
            let itemProtection: CleanupProtection = sourceName?.localizedCaseInsensitiveContains("Docker") == true
                ? .reviewOnly
                : protection(for: root, category: category, risk: risk)

            let item = CleanupItem(
                url: root,
                name: root.lastPathComponent,
                size: size,
                modifiedAt: values?.contentModificationDate,
                category: category,
                risk: risk,
                reason: reason,
                isDirectory: true,
                protection: itemProtection,
                sourceKind: sourceKind ?? CleanupItem.defaultSourceKind(for: category),
                sourceName: sourceName,
                sourceWarning: sourceWarning
            )
            items.append(item)
            await onItem(item)
            await onSummary(summary)
        }
    }

    private func collectPythonBytecodeCandidates(
        roots: [URL],
        items: inout [CleanupItem],
        seenPaths: inout Set<String>,
        summary: inout ScanSummary,
        excludedPaths: [String],
        phase: ScanPhase,
        shouldStopPhase: @escaping (ScanPhase) async -> Bool,
        onItem: @escaping @MainActor @Sendable (CleanupItem) -> Void,
        onSummary: @escaping @MainActor @Sendable (ScanSummary) -> Void
    ) async {
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]

        for root in roots where fileManager.fileExists(atPath: root.path) && !isExcluded(root, excludedPaths: excludedPaths) {
            if await shouldStopPhase(phase) { return }
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else {
                summary.skippedItems += 1
                continue
            }

            while let url = enumerator.nextObject() as? URL {
                if await shouldStopPhase(phase) { return }
                if isExcluded(url, excludedPaths: excludedPaths) || isSystemCritical(url) {
                    enumerator.skipDescendants()
                    continue
                }
                guard url.lastPathComponent == "__pycache__", seenPaths.insert(url.path).inserted else { continue }

                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
                guard values?.isDirectory == true else { continue }
                let size = directorySize(url, maxDepth: 2, summary: &summary)
                guard size >= 256 * 1_024 else {
                    enumerator.skipDescendants()
                    continue
                }

                let item = CleanupItem(
                    url: url,
                    name: url.lastPathComponent,
                    size: size,
                    modifiedAt: values?.contentModificationDate,
                    category: .developerData,
                    risk: .low,
                    reason: "Python bytecode cache",
                    isDirectory: true,
                    protection: .normal,
                    sourceKind: .developer,
                    sourceName: "Python __pycache__",
                    sourceWarning: "Python bytecode caches are regenerated automatically. Review project paths before removing."
                )
                items.append(item)
                await onItem(item)
                await onSummary(summary)
                enumerator.skipDescendants()
            }
        }
    }

    private func collectFileCandidates(
        roots: [URL],
        category: CleanupCategory,
        reason: String,
        risk: CleanupRisk,
        minSize: Int64,
        olderThanDays: Int?,
        fileExtensions: Set<String>? = nil,
        items: inout [CleanupItem],
        seenPaths: inout Set<String>,
        summary: inout ScanSummary,
        excludedPaths: [String],
        sourceKind: CleanupSourceKind? = nil,
        sourceName: String? = nil,
        sourceWarning: String? = nil,
        phase: ScanPhase,
        shouldStopPhase: @escaping (ScanPhase) async -> Bool,
        onItem: @escaping @MainActor @Sendable (CleanupItem) -> Void,
        onSummary: @escaping @MainActor @Sendable (ScanSummary) -> Void
    ) async {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]
        let cutoff = olderThanDays.map { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) ?? Date.distantPast }

        for root in roots where fileManager.fileExists(atPath: root.path) && !isExcluded(root, excludedPaths: excludedPaths) {
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
                if await shouldStopPhase(phase) { return }
                let url = nextURL
                if isExcluded(url, excludedPaths: excludedPaths) {
                    if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }
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
                if let fileExtensions, !fileExtensions.contains(url.pathExtension.lowercased()) { continue }

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
                    isDirectory: false,
                    protection: protection(for: url, category: category, risk: risk),
                    sourceKind: sourceKind ?? CleanupItem.defaultSourceKind(for: category),
                    sourceName: sourceName,
                    sourceWarning: sourceWarning
                )
                items.append(item)
                await onItem(item)
                await onSummary(summary)
            }
        }
    }

    private func collectDuplicateFileCandidates(
        roots: [URL],
        minSize: Int64,
        items: inout [CleanupItem],
        seenPaths: inout Set<String>,
        summary: inout ScanSummary,
        excludedPaths: [String],
        phase: ScanPhase,
        shouldStopPhase: @escaping (ScanPhase) async -> Bool,
        onItem: @escaping @MainActor @Sendable (CleanupItem) -> Void,
        onSummary: @escaping @MainActor @Sendable (ScanSummary) -> Void
    ) async {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]
        var filesBySize: [Int64: [URL]] = [:]

        for root in roots where fileManager.fileExists(atPath: root.path) && !isExcluded(root, excludedPaths: excludedPaths) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else {
                summary.skippedItems += 1
                continue
            }

            while let url = enumerator.nextObject() as? URL {
                if await shouldStopPhase(phase) { return }
                if isExcluded(url, excludedPaths: excludedPaths) {
                    if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                guard !isProtectedPath(url), !isSystemCritical(url) else { continue }
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else {
                    summary.skippedItems += 1
                    continue
                }
                summary.scannedFiles += 1
                let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                guard size >= minSize else { continue }
                filesBySize[size, default: []].append(url)
            }
        }

        // Tiered matching: files sharing a size are first compared by a 64 KB
        // prefix hash; only prefix collisions pay for a full-file hash.
        let prefixLimit: Int64 = 64 * 1_024
        for (size, urls) in filesBySize where urls.count > 1 {
            if await shouldStopPhase(phase) { return }
            var filesByPrefix: [String: [URL]] = [:]
            let prefixHashes = await hashBatch(urls, maxBytes: prefixLimit)
            for (url, prefixHash) in zip(urls, prefixHashes) {
                guard let prefixHash else {
                    summary.skippedItems += 1
                    continue
                }
                filesByPrefix[prefixHash, default: []].append(url)
            }

            var filesByHash: [String: [URL]] = [:]
            for (prefixHash, candidates) in filesByPrefix where candidates.count > 1 {
                if await shouldStopPhase(phase) { return }
                if size <= prefixLimit {
                    filesByHash[prefixHash] = candidates
                    continue
                }
                let fullHashes = await hashBatch(candidates, maxBytes: nil)
                for (url, hash) in zip(candidates, fullHashes) {
                    guard let hash else {
                        summary.skippedItems += 1
                        continue
                    }
                    filesByHash[hash, default: []].append(url)
                }
            }

            for (hash, matches) in filesByHash where matches.count > 1 {
                let groupID = "\(size)-\(hash.prefix(12))"
                for url in matches.sorted(by: { $0.path < $1.path }) {
                    guard seenPaths.insert(url.path).inserted else { continue }
                    let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    let item = CleanupItem(
                        url: url,
                        name: url.lastPathComponent,
                        size: size,
                        modifiedAt: values?.contentModificationDate,
                        category: .duplicates,
                        risk: .medium,
                        reason: "Duplicate file group with \(matches.count) matches",
                        isDirectory: false,
                        protection: protection(for: url, category: .duplicates, risk: .medium),
                        duplicateGroupID: groupID,
                        duplicateCount: matches.count,
                        sourceKind: .duplicate,
                        sourceName: "SHA-256 Duplicates"
                    )
                    items.append(item)
                    await onItem(item)
                    await onSummary(summary)
                }
            }
        }
    }

    private func collectBrowserCacheCandidates(
        roots: [BrowserCacheRoot],
        items: inout [CleanupItem],
        seenPaths: inout Set<String>,
        summary: inout ScanSummary,
        excludedPaths: [String],
        phase: ScanPhase,
        shouldStopPhase: @escaping (ScanPhase) async -> Bool,
        onItem: @escaping @MainActor @Sendable (CleanupItem) -> Void,
        onSummary: @escaping @MainActor @Sendable (ScanSummary) -> Void
    ) async {
        for root in roots where fileManager.fileExists(atPath: root.url.path) && !isExcluded(root.url, excludedPaths: excludedPaths) {
            if await shouldStopPhase(phase) { return }
            guard !isSystemCritical(root.url), seenPaths.insert(root.url.path).inserted else { continue }
            let values = try? root.url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            guard values?.isDirectory == true else { continue }

            let size = directorySize(root.url, maxDepth: 4, summary: &summary)
            guard size >= 5 * 1_024 * 1_024 else { continue }
            let profileText = root.profileName.map { " profile \($0)" } ?? ""
            let item = CleanupItem(
                url: root.url,
                name: root.url.lastPathComponent,
                size: size,
                modifiedAt: values?.contentModificationDate,
                category: .caches,
                risk: .medium,
                reason: "\(root.browserName)\(profileText) browser cache",
                isDirectory: true,
                protection: .reviewOnly,
                sourceKind: .browser,
                sourceName: root.profileName.map { "\(root.browserName) - \($0)" } ?? root.browserName,
                sourceWarning: "Only cache folders are targeted. Cookies, passwords, bookmarks, history, sessions, and profile databases stay protected."
            )
            items.append(item)
            await onItem(item)
            await onSummary(summary)
        }
    }

    private func collectAppLeftoverCandidates(
        home: URL,
        items: inout [CleanupItem],
        seenPaths: inout Set<String>,
        summary: inout ScanSummary,
        excludedPaths: [String],
        phase: ScanPhase,
        shouldStopPhase: @escaping (ScanPhase) async -> Bool,
        onItem: @escaping @MainActor @Sendable (CleanupItem) -> Void,
        onSummary: @escaping @MainActor @Sendable (ScanSummary) -> Void
    ) async {
        let installedBundleIDs = installedApplicationBundleIDs(home: home)
        let roots = [
            home.appendingPathComponent("Library/Caches"),
            home.appendingPathComponent("Library/Application Support"),
            home.appendingPathComponent("Library/Containers"),
            home.appendingPathComponent("Library/HTTPStorages"),
            home.appendingPathComponent("Library/WebKit"),
            home.appendingPathComponent("Library/Preferences"),
            home.appendingPathComponent("Library/Logs"),
            home.appendingPathComponent("Library/LaunchAgents"),
            URL(fileURLWithPath: "/Library/LaunchAgents"),
            URL(fileURLWithPath: "/Library/LaunchDaemons"),
            URL(fileURLWithPath: "/Library/Receipts"),
            URL(fileURLWithPath: "/private/var/db/receipts")
        ]

        for root in roots where fileManager.fileExists(atPath: root.path) && !isExcluded(root, excludedPaths: excludedPaths) {
            if await shouldStopPhase(phase) { return }
            guard let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                summary.skippedItems += 1
                continue
            }

            for child in children {
                if await shouldStopPhase(phase) { return }
                guard !isExcluded(child, excludedPaths: excludedPaths) else { continue }
                guard let match = appLeftoverMatch(from: child),
                      !installedBundleIDs.contains(match.bundleID),
                      !isAppleOwnedBundleID(match.bundleID) else { continue }
                guard !isProtectedPath(child), seenPaths.insert(child.path).inserted else { continue }
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
                let isDirectory = values?.isDirectory ?? true
                let size = isDirectory ? directorySize(child, maxDepth: 3, summary: &summary) : fileSize(child)
                guard size >= minimumLeftoverSize(for: child) else { continue }
                let item = CleanupItem(
                    url: child,
                    name: child.lastPathComponent,
                    size: size,
                    modifiedAt: values?.contentModificationDate,
                    category: .appLeftovers,
                    risk: .medium,
                    reason: "\(match.confidence.rawValue) leftover data for uninstalled app \(match.bundleID)",
                    isDirectory: isDirectory,
                    protection: .reviewOnly,
                    relatedBundleID: match.bundleID,
                    sourceKind: .appLeftover,
                    sourceName: match.bundleID,
                    sourceWarning: "\(match.confidence.explanation) Review before removing.",
                    appLeftoverConfidence: match.confidence
                )
                items.append(item)
                await onItem(item)
                await onSummary(summary)
            }
        }
    }

    private func minimumLeftoverSize(for url: URL) -> Int64 {
        let path = url.path
        if path.contains("/Library/Preferences/") || path.contains("/Library/LaunchAgents/") ||
            path.contains("/Library/LaunchDaemons/") || path.contains("/Library/Receipts/") ||
            path.contains("/private/var/db/receipts/") {
            return 1_024
        }
        if path.contains("/Library/Logs/") {
            return 100 * 1_024
        }
        return 1_024 * 1_024
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
            if Task.isCancelled { return total }
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

    private func fileSize(_ url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.fileAllocatedSizeKey, .totalFileAllocatedSizeKey]) else {
            return 0
        }
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
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
            "/Library/Application Support/MobileSync/",
            "/Library/Application Support/Google/Chrome/",
            "/Library/Application Support/Microsoft Edge/",
            "/Library/Application Support/Firefox/"
        ]
        return excludedFragments.contains { path.contains($0) }
    }

    private func normalizedExcludedPaths(_ paths: [String]) -> [String] {
        paths
            .map { NSString(string: $0).expandingTildeInPath }
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            .filter { !$0.isEmpty && $0 != "/" }
            .sorted()
    }

    private func isExcluded(_ url: URL, excludedPaths: [String]) -> Bool {
        guard !excludedPaths.isEmpty else { return false }
        let path = url.standardizedFileURL.path
        return excludedPaths.contains { excludedPath in
            path == excludedPath || path.hasPrefix("\(excludedPath)/")
        }
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

    private func isProtectedPath(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let home = fileManager.homeDirectoryForCurrentUser.standardizedFileURL.path
        let protectedExact = [
            home,
            "\(home)/Desktop",
            "\(home)/Documents",
            "\(home)/Downloads",
            "\(home)/Library",
            "\(home)/Library/Application Support",
            "\(home)/Library/Containers",
            "\(home)/Library/Group Containers",
            "\(home)/Pictures",
            "\(home)/Movies",
            "\(home)/Music",
            "\(home)/Library/Mail",
            "\(home)/Library/Messages",
            "\(home)/Library/Photos",
            "\(home)/Library/CloudStorage"
        ]
        let protectedPrefixes = [
            "\(home)/Library/Application Support/MobileSync",
            "\(home)/Pictures/Photos Library.photoslibrary",
            "\(home)/Library/Keychains",
            "\(home)/Library/Accounts",
            "\(home)/Library/Calendars",
            "\(home)/Library/AddressBook"
        ]
        let sensitiveBrowserPrefixes = [
            "\(home)/Library/Application Support/Google/Chrome",
            "\(home)/Library/Application Support/Microsoft Edge",
            "\(home)/Library/Application Support/Firefox",
            "\(home)/Library/Safari"
        ]

        return protectedExact.contains(path) ||
            protectedPrefixes.contains { path.hasPrefix($0) } ||
            sensitiveBrowserPrefixes.contains { path.hasPrefix($0) && !path.contains("/Cache") && !path.contains("/cache2") }
    }

    private func protection(for url: URL, category: CleanupCategory, risk: CleanupRisk) -> CleanupProtection {
        if isProtectedPath(url) || isSystemCritical(url) {
            return .neverDelete
        }

        switch category {
        case .systemStorage:
            return .neverDelete
        case .appSupport, .oldFiles:
            return .reviewOnly
        case .downloads where risk == .medium:
            return .reviewOnly
        case .duplicates, .appLeftovers:
            return .reviewOnly
        default:
            return .normal
        }
    }

    /// Hashes each URL concurrently (bounded), preserving input order.
    private nonisolated func hashBatch(_ urls: [URL], maxBytes: Int64?) async -> [String?] {
        await withTaskGroup(of: (Int, String?).self) { group in
            var results = [String?](repeating: nil, count: urls.count)
            let concurrency = min(4, urls.count)
            var nextIndex = 0

            func addTask(_ index: Int) {
                group.addTask {
                    (index, self.sha256(for: urls[index], maxBytes: maxBytes))
                }
            }

            while nextIndex < concurrency {
                addTask(nextIndex)
                nextIndex += 1
            }
            for await (index, hash) in group {
                results[index] = hash
                if nextIndex < urls.count {
                    addTask(nextIndex)
                    nextIndex += 1
                }
            }
            return results
        }
    }

    private nonisolated func sha256(for url: URL, maxBytes: Int64? = nil) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        var remaining = maxBytes ?? .max
        while remaining > 0 {
            if Task.isCancelled { return nil }
            let chunkSize = Int(min(Int64(1_024 * 1_024), remaining))
            let data = handle.readData(ofLength: chunkSize)
            if data.isEmpty { break }
            hasher.update(data: data)
            remaining -= Int64(data.count)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func installedApplicationBundleIDs(home: URL) -> Set<String> {
        let appRoots = [
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/Applications/Setapp"),
            URL(fileURLWithPath: "/Users/Shared/Applications"),
            home.appendingPathComponent("Applications"),
            home.appendingPathComponent("Applications/Setapp")
        ]
        var bundleIDs = Set<String>()

        for root in Set(appRoots.map(\.standardizedFileURL)).sorted(by: { $0.path < $1.path }) where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else { continue }

            while let url = enumerator.nextObject() as? URL {
                guard url.pathExtension == "app" else { continue }
                if let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier {
                    bundleIDs.insert(bundleID)
                }
                enumerator.skipDescendants()
            }
        }

        return bundleIDs
    }

    private func appLeftoverMatch(from url: URL) -> (bundleID: String, confidence: AppLeftoverConfidence)? {
        let path = url.path
        let bundleID = probableBundleID(from: url)
        let confidence: AppLeftoverConfidence
        if path.contains("/Library/Receipts/") || path.contains("/private/var/db/receipts/") ||
            path.contains("/Library/Preferences/") || path.contains("/Library/LaunchAgents/") ||
            path.contains("/Library/LaunchDaemons/") {
            confidence = .exactBundleID
        } else if path.contains("/Library/Containers/") || path.contains("/Library/HTTPStorages/") || path.contains("/Library/WebKit/") {
            confidence = .probableBundleID
        } else if path.contains("/Library/Logs/"), bundleID == nil {
            guard let logIdentifier = logLeftoverIdentifier(from: url) else { return nil }
            return (logIdentifier, .weakNameMatch)
        } else {
            confidence = .weakNameMatch
        }

        guard let probableBundleID = bundleID else { return nil }
        return (probableBundleID, confidence)
    }

    private func probableBundleID(from url: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent
        guard name.contains(".") else { return nil }
        let parts = name.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        guard name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return name
    }

    private func isAppleOwnedBundleID(_ bundleID: String) -> Bool {
        bundleID.hasPrefix("com.apple.")
    }

    private func logLeftoverIdentifier(from url: URL) -> String? {
        if let children = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for child in children {
                if let bundleID = probableBundleID(from: child) {
                    return bundleID
                }
            }
        }

        let name = url.deletingPathExtension().lastPathComponent
        let normalized = name
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let ignoredNames = Set(["log", "logs", "crashreporter", "diagnosticreports", "diagnostics"])
        guard normalized.count >= 3, !ignoredNames.contains(normalized) else { return nil }
        return "log.\(normalized)"
    }

    private func developerDataRoots(home: URL) -> [DeveloperDataRoot] {
        [
            DeveloperDataRoot(url: home.appendingPathComponent("Library/Developer/Xcode/DerivedData"), sourceName: "Xcode DerivedData", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent("Library/Developer/Xcode/Archives"), sourceName: "Xcode Archives", warning: "Archives may be needed for symbolication or re-distribution."),
            DeveloperDataRoot(url: home.appendingPathComponent("Library/Developer/Xcode/Products"), sourceName: "Xcode Products", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent("Library/Developer/Xcode/UserData/Previews"), sourceName: "Xcode Previews", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport"), sourceName: "Xcode DeviceSupport", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent("Library/Developer/CoreSimulator/Devices"), sourceName: "Simulator Devices", warning: "Simulator devices can contain app data used for development."),
            DeveloperDataRoot(url: home.appendingPathComponent("Library/Developer/CoreSimulator/Caches"), sourceName: "Simulator Caches", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent("Library/Developer/CoreSimulator/Profiles/Runtimes"), sourceName: "Simulator Runtimes", warning: "Old simulator runtimes can be several gigabytes each. Remove runtimes you no longer target; Xcode can reinstall them."),
            DeveloperDataRoot(url: home.appendingPathComponent("Library/Developer/XCTestDevices"), sourceName: "XCTest Devices", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent("Library/Caches/com.apple.dt.Xcode"), sourceName: "Xcode Cache", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent("Library/Caches/org.swift.swiftpm"), sourceName: "SwiftPM Cache", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent("Library/Caches/Homebrew"), sourceName: "Homebrew Cache", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent(".npm"), sourceName: "npm Cache", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent(".npm/_cacache"), sourceName: "npm Content Cache", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent(".cache/yarn"), sourceName: "Yarn Cache", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent("Library/Caches/Yarn"), sourceName: "Yarn Cache", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent(".pnpm-store"), sourceName: "pnpm Store", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent(".cache/pnpm"), sourceName: "pnpm Cache", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent("Library/pnpm/store"), sourceName: "pnpm Store", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent("Library/Caches/pip"), sourceName: "pip Cache", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent(".cache/pip"), sourceName: "pip Cache", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent("Library/Caches/pypoetry"), sourceName: "Poetry Cache", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent(".cache/pypoetry"), sourceName: "Poetry Cache", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent(".local/share/virtualenvs"), sourceName: "Pipenv Virtualenvs", warning: "Virtualenvs may contain project-specific Python environments."),
            DeveloperDataRoot(url: home.appendingPathComponent("Library/Caches/virtualenv"), sourceName: "virtualenv Cache", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent(".pyenv/cache"), sourceName: "pyenv Build Cache", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent(".pyenv/sources"), sourceName: "pyenv Sources", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent(".gradle/caches"), sourceName: "Gradle Cache", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent(".gradle/wrapper/dists"), sourceName: "Gradle Wrapper Distributions", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent(".m2/repository"), sourceName: "Maven Repository", warning: "Maven dependencies may need to be downloaded again."),
            DeveloperDataRoot(url: home.appendingPathComponent(".cache/go-build"), sourceName: "Go Build Cache", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent("go/pkg/mod/cache"), sourceName: "Go Module Cache", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent(".cargo/registry/cache"), sourceName: "Cargo Registry Cache", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent(".cargo/git/checkouts"), sourceName: "Cargo Git Checkouts", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent(".rustup/downloads"), sourceName: "Rustup Downloads", warning: nil),
            DeveloperDataRoot(url: home.appendingPathComponent("Library/Containers/com.docker.docker/Data/vms"), sourceName: "Docker VM Storage", warning: "Review-only. Docker VM storage can include images, containers, volumes, and Docker.raw. Prefer Docker prune commands and stop Docker before manual cleanup."),
            DeveloperDataRoot(url: home.appendingPathComponent("Library/Containers/com.docker.docker/Data/vms/0/data"), sourceName: "Docker Images and Volumes", warning: "Review-only. This location can contain Docker.raw, images, containers, and volumes; do not remove while Docker is running."),
            DeveloperDataRoot(url: home.appendingPathComponent("Library/Group Containers/group.com.docker/cache"), sourceName: "Docker Build Cache", warning: "Review-only. Prefer Docker prune commands for cache cleanup."),
            DeveloperDataRoot(url: home.appendingPathComponent("Library/Group Containers/group.com.docker/Library/Caches"), sourceName: "Docker App Cache", warning: "Review-only. Prefer Docker Desktop cleanup controls for app cache cleanup.")
        ]
    }

    private func developerSource(for url: URL, home: URL) -> DeveloperDataRoot? {
        developerDataRoots(home: home).first { root in
            url.standardizedFileURL.path == root.url.standardizedFileURL.path
        }
    }

    private func pythonProjectRoots(home: URL) -> [URL] {
        [
            home.appendingPathComponent("Developer"),
            home.appendingPathComponent("Projects"),
            home.appendingPathComponent("Code"),
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("src"),
            home.appendingPathComponent("work")
        ]
    }

    private func browserCacheRoots(home: URL) -> [BrowserCacheRoot] {
        var roots: [BrowserCacheRoot] = [
            BrowserCacheRoot(url: home.appendingPathComponent("Library/Caches/com.apple.Safari"), browserName: "Safari", profileName: nil),
            BrowserCacheRoot(url: home.appendingPathComponent("Library/Caches/Google/Chrome"), browserName: "Chrome", profileName: nil),
            BrowserCacheRoot(url: home.appendingPathComponent("Library/Caches/Microsoft Edge"), browserName: "Edge", profileName: nil),
            BrowserCacheRoot(url: home.appendingPathComponent("Library/Caches/Firefox"), browserName: "Firefox", profileName: nil)
        ]

        roots.append(contentsOf: chromiumProfileCaches(
            browserName: "Chrome",
            base: home.appendingPathComponent("Library/Application Support/Google/Chrome")
        ))
        roots.append(contentsOf: chromiumProfileCaches(
            browserName: "Edge",
            base: home.appendingPathComponent("Library/Application Support/Microsoft Edge")
        ))
        roots.append(contentsOf: firefoxProfileCaches(
            base: home.appendingPathComponent("Library/Application Support/Firefox/Profiles")
        ))

        return roots
    }

    private func chromiumProfileCaches(browserName: String, base: URL) -> [BrowserCacheRoot] {
        guard let profiles = try? fileManager.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return profiles.compactMap { profile in
            guard (try? profile.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let name = profile.lastPathComponent
            guard name == "Default" || name.hasPrefix("Profile ") else { return nil }
            return BrowserCacheRoot(
                url: profile.appendingPathComponent("Cache", isDirectory: true),
                browserName: browserName,
                profileName: name
            )
        }
    }

    private func firefoxProfileCaches(base: URL) -> [BrowserCacheRoot] {
        guard let profiles = try? fileManager.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return profiles.compactMap { profile in
            guard (try? profile.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            return BrowserCacheRoot(
                url: profile.appendingPathComponent("cache2", isDirectory: true),
                browserName: "Firefox",
                profileName: profile.lastPathComponent
            )
        }
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
