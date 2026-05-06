import AppKit
import Foundation

@MainActor
final class CleanupManager: ObservableObject {
    @Published var options = ScanOptions()
    @Published var scanMode: ScanMode = .quick
    @Published var items: [CleanupItem] = []
    @Published var selectedIDs = Set<CleanupItem.ID>()
    @Published var summary = ScanSummary()
    @Published var state: ScanState = .idle
    @Published var lastDeletionMessage: String?
    @Published var fullDiskAccessStatus = FullDiskAccessService.currentStatus()
    @Published var detailItem: CleanupItem?
    @Published var trashHistory: [TrashHistoryEntry] = []
    @Published var diskSpace = DiskSpaceSnapshot()

    private let scanner = FileScanner()
    private var lastScannedAt: Date?
    private var scanTask: Task<Void, Never>?

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
        if let stored = ScanResultsStore.load() {
            items = stored.items
            summary = stored.summary
            summary.reclaimableBytes = items.filter(\.existsOnDisk).reduce(0) { $0 + $1.size }
            lastScannedAt = stored.scannedAt
            state = .finished
        }
        trashHistory = ScanResultsStore.loadTrashHistory()
        refreshDiskSpace()
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
            options.includeAppSupport = true
            options.includeSystemStorage = true
        case .custom:
            break
        }
    }

    func markCustomScanMode() {
        scanMode = .custom
    }

    private func appendStreamedItem(_ item: CleanupItem) {
        guard !items.contains(where: { $0.path == item.path }) else { return }
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

    private static let scanDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
