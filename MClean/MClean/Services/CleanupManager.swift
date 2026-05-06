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

    private let scanner = FileScanner()
    private var lastScannedAt: Date?
    private var scanTask: Task<Void, Never>?

    var selectedItems: [CleanupItem] {
        items.filter { selectedIDs.contains($0.id) }
    }

    var selectedBytes: Int64 {
        selectedItems.filter(\.existsOnDisk).reduce(0) { $0 + $1.size }
    }

    var missingItemCount: Int {
        items.filter { !$0.existsOnDisk }.count
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
    }

    func scan() {
        guard scanTask == nil else { return }
        selectedIDs.removeAll()
        lastDeletionMessage = nil
        items.removeAll()
        summary = ScanSummary()
        refreshFullDiskAccessStatus()
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
                self.summary.reclaimableBytes = self.items.filter(\.existsOnDisk).reduce(0) { $0 + $1.size }
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
            options.includeOldFiles = false
            options.includeDeveloperData = true
            options.includeAppSupport = false
            options.includeSystemStorage = false
        case .deep:
            options.includeCaches = true
            options.includeDownloads = true
            options.includeTemporary = true
            options.includeLargeFiles = true
            options.includeOldFiles = true
            options.includeDeveloperData = true
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
        summary.reclaimableBytes = items.filter(\.existsOnDisk).reduce(0) { $0 + $1.size }
    }

    func refreshFullDiskAccessStatus() {
        fullDiskAccessStatus = FullDiskAccessService.currentStatus()
    }

    func openFullDiskAccessSettings() {
        FullDiskAccessService.openSettings()
    }

    func toggleSelection(for item: CleanupItem) {
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
        selectedIDs.formUnion(visibleItems.filter(\.existsOnDisk).map(\.id))
    }

    func clearSelection() {
        selectedIDs.removeAll()
    }

    func reveal(_ item: CleanupItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func removeMissingItems() {
        items.removeAll { !$0.existsOnDisk }
        selectedIDs = selectedIDs.intersection(Set(items.map(\.id)))
        summary.reclaimableBytes = items.filter(\.existsOnDisk).reduce(0) { $0 + $1.size }
        ScanResultsStore.save(items: items, summary: summary)
    }

    func moveSelectedToTrash() {
        let targets = selectedItems.filter(\.existsOnDisk)
        guard !targets.isEmpty else { return }

        var removed = 0
        var failed = 0
        for item in targets {
            do {
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: item.url, resultingItemURL: &resultingURL)
                removed += 1
            } catch {
                failed += 1
            }
        }

        let removedIDs = Set(targets.map(\.id))
        items.removeAll { removedIDs.contains($0.id) && !FileManager.default.fileExists(atPath: $0.path) }
        selectedIDs.subtract(removedIDs)
        summary.reclaimableBytes = items.filter(\.existsOnDisk).reduce(0) { $0 + $1.size }
        lastDeletionMessage = failed == 0
            ? "Moved \(removed) item\(removed == 1 ? "" : "s") to Trash."
            : "Moved \(removed) item\(removed == 1 ? "" : "s") to Trash. \(failed) failed."
        ScanResultsStore.save(items: items, summary: summary)
    }

    private static let scanDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
