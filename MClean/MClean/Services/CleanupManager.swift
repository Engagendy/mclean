import AppKit
import Foundation

@MainActor
final class CleanupManager: ObservableObject {
    @Published var options = ScanOptions() {
        didSet {
            guard isReadyToPersistPreferences else { return }
            savePreferences()
        }
    }
    @Published var scanMode: ScanMode = .quick {
        didSet {
            guard isReadyToPersistPreferences else { return }
            savePreferences()
        }
    }
    @Published var items: [CleanupItem] = []
    @Published var selectedIDs = Set<CleanupItem.ID>()
    @Published var summary = ScanSummary()
    @Published var state: ScanState = .idle
    @Published var lastDeletionMessage: String?
    @Published var fullDiskAccessStatus = FullDiskAccessService.currentStatus()
    @Published var detailItem: CleanupItem?
    @Published var trashHistory: [TrashHistoryEntry] = []
    @Published var stageEntries: [StageEntry] = []
    @Published var diskSpace = DiskSpaceSnapshot()

    private let scanner = FileScanner()
    private var lastScannedAt: Date?
    private var scanTask: Task<Void, Never>?
    private var isReadyToPersistPreferences = false

    var selectedItems: [CleanupItem] {
        items.filter { selectedIDs.contains($0.id) }
    }

    var selectedBytes: Int64 {
        selectedItems.filter(\.canMoveToTrash).reduce(0) { $0 + $1.size }
    }

    var missingItemCount: Int {
        items.filter { !$0.existsOnDisk }.count
    }

    var categoryTotals: [(category: CleanupCategory, bytes: Int64)] {
        CleanupCategory.allCases.compactMap { category in
            let bytes = items
                .filter { $0.category == category && $0.existsOnDisk }
                .reduce(Int64(0)) { $0 + $1.size }
            return bytes > 0 ? (category, bytes) : nil
        }
        .sorted { $0.bytes > $1.bytes }
    }

    var protectedItemCount: Int {
        items.filter { !$0.canMoveToTrash }.count
    }

    var lastScanDescription: String? {
        guard let lastScannedAt else { return nil }
        return Self.scanDateFormatter.string(from: lastScannedAt)
    }

    init() {
        let preferences = ScanResultsStore.loadPreferences()
        options = preferences.options
        scanMode = preferences.scanMode
        if let stored = ScanResultsStore.load() {
            items = stored.items
            summary = stored.summary
            summary.reclaimableBytes = items.filter(\.existsOnDisk).reduce(0) { $0 + $1.size }
            lastScannedAt = stored.scannedAt
            state = .finished
        }
        trashHistory = ScanResultsStore.loadTrashHistory()
        stageEntries = ScanResultsStore.loadStageEntries()
        refreshDiskSpace()
        isReadyToPersistPreferences = true
    }

    func scan() {
        guard scanTask == nil else { return }
        selectedIDs.removeAll()
        lastDeletionMessage = nil
        items.removeAll()
        summary = ScanSummary()
        refreshFullDiskAccessStatus()
        refreshDiskSpace()
        state = .scanning("Preparing scan")

        scanTask = Task { [weak self] in
            guard let self else { return }
            let result = await scanner.scan(
                options: options,
                progress: { [weak self] message in
                    guard let self, self.scanTask != nil else { return }
                    self.state = .scanning(message)
                },
                onItem: { [weak self] item in
                    guard let self, self.scanTask != nil else { return }
                    self.appendStreamedItem(item)
                },
                onSummary: { [weak self] summary in
                    guard let self, self.scanTask != nil else { return }
                    self.summary.scannedFiles = summary.scannedFiles
                    self.summary.skippedItems = summary.skippedItems
                    self.summary.protectedLocationsBlocked = summary.protectedLocationsBlocked
                }
            )

            guard !Task.isCancelled else {
                self.summary.reclaimableBytes = self.items.filter(\.canMoveToTrash).reduce(0) { $0 + $1.size }
                self.lastScannedAt = Date()
                ScanResultsStore.save(items: self.items, summary: self.summary)
                self.scanTask = nil
                self.state = .cancelled
                return
            }

            items = result.items
            summary = result.summary
            lastScannedAt = Date()
            ScanResultsStore.save(items: items, summary: summary)
            refreshFullDiskAccessStatus()
            refreshDiskSpace()
            scanTask = nil
            state = .finished
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    var isScanning: Bool {
        scanTask != nil
    }

    func applyScanMode(_ mode: ScanMode) {
        scanMode = mode
        switch mode {
        case .quick:
            options.includeCaches = true
            options.includeDownloads = true
            options.includeTemporary = true
            options.includeLargeFiles = true
            options.includeDuplicates = true
            options.includeOldFiles = false
            options.includeDeveloperData = true
            options.includeAppLeftovers = true
            options.includeBrowserCaches = false
            options.includeAppSupport = false
            options.includeSystemStorage = false
        case .deep:
            options.includeCaches = true
            options.includeDownloads = true
            options.includeTemporary = true
            options.includeLargeFiles = true
            options.includeDuplicates = true
            options.includeOldFiles = true
            options.includeDeveloperData = true
            options.includeAppLeftovers = true
            options.includeBrowserCaches = true
            options.includeAppSupport = true
            options.includeSystemStorage = true
        case .developer:
            options.includeCaches = false
            options.includeDownloads = false
            options.includeTemporary = false
            options.includeLargeFiles = false
            options.includeDuplicates = false
            options.includeOldFiles = false
            options.includeDeveloperData = true
            options.includeAppLeftovers = false
            options.includeBrowserCaches = false
            options.includeAppSupport = false
            options.includeSystemStorage = false
        case .downloadsReview:
            options.includeCaches = false
            options.includeDownloads = true
            options.includeTemporary = false
            options.includeLargeFiles = true
            options.includeDuplicates = true
            options.includeOldFiles = true
            options.includeDeveloperData = false
            options.includeAppLeftovers = false
            options.includeBrowserCaches = false
            options.includeAppSupport = false
            options.includeSystemStorage = false
        case .custom:
            break
        }
    }

    func markCustomScanMode() {
        scanMode = .custom
    }

    func updateOptions(_ update: (inout ScanOptions) -> Void) {
        var next = options
        update(&next)
        options = next
    }

    func addExcludedPath(_ path: String) {
        let normalized = normalizedPath(path)
        guard !normalized.isEmpty, normalized != "/" else { return }
        guard !options.excludedPaths.contains(normalized) else { return }
        updateOptions { options in
            options.excludedPaths.append(normalized)
            options.excludedPaths.sort()
        }
        removeItemsExcludedByPreferences()
        lastDeletionMessage = "Excluded \(normalized)."
    }

    func removeExcludedPath(_ path: String) {
        updateOptions { options in
            options.excludedPaths.removeAll { $0 == path }
        }
        lastDeletionMessage = "Removed scan exclusion."
    }

    func excludeParentFolder(of item: CleanupItem) {
        addExcludedPath(item.url.deletingLastPathComponent().path)
        markCustomScanMode()
    }

    private func appendStreamedItem(_ item: CleanupItem) {
        guard !items.contains(where: { $0.path == item.path }) else { return }
        guard !isExcludedByPreferences(item.url) else { return }
        items.append(item)
        if items.count > options.maxResults {
            items.sort { $0.size > $1.size }
            items.removeLast(items.count - options.maxResults)
        }
        summary.reclaimableBytes = items.filter(\.canMoveToTrash).reduce(0) { $0 + $1.size }
    }

    func refreshFullDiskAccessStatus() {
        fullDiskAccessStatus = FullDiskAccessService.currentStatus()
    }

    func openFullDiskAccessSettings() {
        FullDiskAccessService.openSettings()
    }

    func refreshDiskSpace() {
        let path = FileManager.default.homeDirectoryForCurrentUser.path
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: path),
              let total = attributes[.systemSize] as? NSNumber,
              let free = attributes[.systemFreeSize] as? NSNumber else {
            diskSpace = DiskSpaceSnapshot()
            return
        }
        diskSpace = DiskSpaceSnapshot(totalBytes: total.int64Value, freeBytes: free.int64Value)
    }

    func toggleSelection(for item: CleanupItem) {
        guard item.canMoveToTrash else { return }
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    func selectRecommended() {
        selectedIDs = Set(items.filter { $0.isRecommendedForCleanup }.map(\.id))
    }

    func select(_ visibleItems: [CleanupItem]) {
        selectedIDs.formUnion(visibleItems.filter(\.canMoveToTrash).map(\.id))
    }

    func clearSelection() {
        selectedIDs.removeAll()
    }

    func reveal(_ item: CleanupItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func showDetails(for item: CleanupItem) {
        detailItem = item
    }

    func removeMissingItems() {
        items.removeAll { !$0.existsOnDisk }
        selectedIDs = selectedIDs.intersection(Set(items.map(\.id)))
        summary.reclaimableBytes = items.filter(\.canMoveToTrash).reduce(0) { $0 + $1.size }
        ScanResultsStore.save(items: items, summary: summary)
        refreshDiskSpace()
    }

    func moveSelectedToTrash() {
        let targets = selectedItems.filter(\.canMoveToTrash)
        guard !targets.isEmpty else { return }

        var removed = 0
        var failed = 0
        var newHistory: [TrashHistoryEntry] = []
        for item in targets {
            do {
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: item.url, resultingItemURL: &resultingURL)
                if let resultingURL = resultingURL as URL? {
                    newHistory.append(TrashHistoryEntry(
                        itemName: item.name,
                        originalURL: item.url,
                        trashedURL: resultingURL,
                        size: item.size,
                        movedAt: Date()
                    ))
                }
                removed += 1
            } catch {
                failed += 1
            }
        }

        let removedIDs = Set(targets.map(\.id))
        items.removeAll { removedIDs.contains($0.id) && !FileManager.default.fileExists(atPath: $0.path) }
        selectedIDs.subtract(removedIDs)
        summary.reclaimableBytes = items.filter(\.canMoveToTrash).reduce(0) { $0 + $1.size }
        if !newHistory.isEmpty {
            trashHistory.insert(contentsOf: newHistory, at: 0)
            trashHistory = Array(trashHistory.prefix(100))
            ScanResultsStore.saveTrashHistory(trashHistory)
        }
        lastDeletionMessage = failed == 0
            ? "Moved \(removed) item\(removed == 1 ? "" : "s") to Trash."
            : "Moved \(removed) item\(removed == 1 ? "" : "s") to Trash. \(failed) failed."
        ScanResultsStore.save(items: items, summary: summary)
        refreshDiskSpace()
    }

    func moveSelectedToStage() {
        let targets = selectedItems.filter(\.canMoveToTrash)
        guard !targets.isEmpty else { return }

        var staged = 0
        var failed = 0
        var newEntries: [StageEntry] = []

        for item in targets {
            do {
                let container = try ScanResultsStore.stageDirectory()
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
                let stagedURL = container.appendingPathComponent(item.name, isDirectory: item.isDirectory)
                try FileManager.default.moveItem(at: item.url, to: stagedURL)
                newEntries.append(StageEntry(
                    itemName: item.name,
                    originalURL: item.url,
                    stagedURL: stagedURL,
                    size: item.size,
                    category: item.category,
                    reason: item.reason,
                    stagedAt: Date()
                ))
                staged += 1
            } catch {
                failed += 1
            }
        }

        let stagedIDs = Set(targets.map(\.id))
        items.removeAll { stagedIDs.contains($0.id) && !FileManager.default.fileExists(atPath: $0.path) }
        selectedIDs.subtract(stagedIDs)
        summary.reclaimableBytes = items.filter(\.canMoveToTrash).reduce(0) { $0 + $1.size }
        if !newEntries.isEmpty {
            stageEntries.insert(contentsOf: newEntries, at: 0)
            ScanResultsStore.saveStageEntries(stageEntries)
        }
        lastDeletionMessage = failed == 0
            ? "Moved \(staged) item\(staged == 1 ? "" : "s") to Stage."
            : "Moved \(staged) item\(staged == 1 ? "" : "s") to Stage. \(failed) failed."
        ScanResultsStore.save(items: items, summary: summary)
        refreshDiskSpace()
    }

    func restoreFromTrash(_ entry: TrashHistoryEntry) {
        guard entry.canRestore else { return }
        do {
            let parent = entry.originalURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: entry.trashedURL, to: entry.originalURL)
            trashHistory.removeAll { $0.id == entry.id }
            ScanResultsStore.saveTrashHistory(trashHistory)
            lastDeletionMessage = "Restored \(entry.itemName)."
            refreshDiskSpace()
        } catch {
            lastDeletionMessage = "Could not restore \(entry.itemName)."
        }
    }

    func restoreFromStage(_ entry: StageEntry) {
        guard entry.canRestore else { return }
        do {
            let parent = entry.originalURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: entry.stagedURL, to: entry.originalURL)
            removeStageContainerIfEmpty(for: entry)
            stageEntries.removeAll { $0.id == entry.id }
            ScanResultsStore.saveStageEntries(stageEntries)
            lastDeletionMessage = "Restored \(entry.itemName)."
            refreshDiskSpace()
        } catch {
            lastDeletionMessage = "Could not restore \(entry.itemName)."
        }
    }

    func moveStagedToTrash(_ entry: StageEntry) {
        guard entry.existsInStage else { return }
        do {
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: entry.stagedURL, resultingItemURL: &resultingURL)
            if let resultingURL = resultingURL as URL? {
                trashHistory.insert(TrashHistoryEntry(
                    itemName: entry.itemName,
                    originalURL: entry.originalURL,
                    trashedURL: resultingURL,
                    size: entry.size,
                    movedAt: Date()
                ), at: 0)
                trashHistory = Array(trashHistory.prefix(100))
                ScanResultsStore.saveTrashHistory(trashHistory)
            }
            removeStageContainerIfEmpty(for: entry)
            stageEntries.removeAll { $0.id == entry.id }
            ScanResultsStore.saveStageEntries(stageEntries)
            lastDeletionMessage = "Moved \(entry.itemName) to Trash."
            refreshDiskSpace()
        } catch {
            lastDeletionMessage = "Could not move \(entry.itemName) to Trash."
        }
    }

    func deleteStagedPermanently(_ entry: StageEntry) {
        guard entry.existsInStage else { return }
        do {
            try FileManager.default.removeItem(at: entry.stagedURL)
            removeStageContainerIfEmpty(for: entry)
            stageEntries.removeAll { $0.id == entry.id }
            ScanResultsStore.saveStageEntries(stageEntries)
            lastDeletionMessage = "Deleted \(entry.itemName)."
            refreshDiskSpace()
        } catch {
            lastDeletionMessage = "Could not delete \(entry.itemName)."
        }
    }

    func removeMissingStageEntry(_ entry: StageEntry) {
        guard !entry.existsInStage else { return }
        stageEntries.removeAll { $0.id == entry.id }
        ScanResultsStore.saveStageEntries(stageEntries)
        lastDeletionMessage = "Removed missing staged item."
    }

    func revealStageFolder() {
        guard let url = try? ScanResultsStore.stageDirectory() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func removeStageContainerIfEmpty(for entry: StageEntry) {
        let container = entry.stagedURL.deletingLastPathComponent()
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: container.path),
              contents.isEmpty else {
            return
        }
        try? FileManager.default.removeItem(at: container)
    }

    private func savePreferences() {
        ScanResultsStore.savePreferences(CleanupPreferences(scanMode: scanMode, options: options))
    }

    private func normalizedPath(_ path: String) -> String {
        let expanded = NSString(string: path.trimmingCharacters(in: .whitespacesAndNewlines)).expandingTildeInPath
        guard !expanded.isEmpty else { return "" }
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    private func isExcludedByPreferences(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return options.excludedPaths.contains { excludedPath in
            path == excludedPath || path.hasPrefix("\(excludedPath)/")
        }
    }

    private func removeItemsExcludedByPreferences() {
        items.removeAll { isExcludedByPreferences($0.url) }
        selectedIDs = selectedIDs.intersection(Set(items.map(\.id)))
        summary.reclaimableBytes = items.filter(\.canMoveToTrash).reduce(0) { $0 + $1.size }
        ScanResultsStore.save(items: items, summary: summary)
    }

    private static let scanDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
