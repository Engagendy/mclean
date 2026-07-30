import AppKit
import Foundation
import UserNotifications

@MainActor
final class CleanupManager: ObservableObject {
    // Single shared instance so the SwiftUI scene and the AppKit status item
    // controller observe the same state.
    static let shared = CleanupManager()

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
    @Published var stageReminderAgeDays = 7 {
        didSet {
            guard isReadyToPersistPreferences else { return }
            savePreferences()
        }
    }
    @Published var showDirectTrashActions = true {
        didSet {
            guard isReadyToPersistPreferences else { return }
            savePreferences()
        }
    }
    @Published var savedScanProfiles: [SavedScanProfile] = [] {
        didSet {
            guard isReadyToPersistPreferences else { return }
            savePreferences()
        }
    }
    @Published var scheduledScansEnabled = false {
        didSet {
            guard isReadyToPersistPreferences else { return }
            if scheduledScansEnabled {
                if lastScheduledScanAt == nil {
                    lastScheduledScanAt = Date()
                }
                requestNotificationAuthorization()
            }
            savePreferences()
        }
    }
    @Published var scheduledScanIntervalDays = 7 {
        didSet {
            guard isReadyToPersistPreferences else { return }
            savePreferences()
        }
    }
    @Published var showMenuBarExtra = true {
        didSet {
            guard isReadyToPersistPreferences else { return }
            savePreferences()
        }
    }
    @Published var items: [CleanupItem] = [] {
        didSet { invalidateDerivedCaches(selectionOnly: false) }
    }
    @Published var selectedIDs = Set<CleanupItem.ID>() {
        didSet { invalidateDerivedCaches(selectionOnly: true) }
    }
    @Published var summary = ScanSummary()
    @Published var state: ScanState = .idle
    @Published var scanProgress = ScanProgress()
    @Published var lastDeletionMessage: String?
    @Published var fullDiskAccessStatus = FullDiskAccessService.currentStatus()
    @Published var detailItem: CleanupItem?
    @Published var trashHistory: [TrashHistoryEntry] = []
    @Published var stageEntries: [StageEntry] = []
    @Published var diskSpace = DiskSpaceSnapshot()
    @Published var localSnapshotCount = 0
    @Published var trashBytes: Int64 = 0

    private let scanner = FileScanner()
    private var lastScannedAt: Date?
    private var lastScheduledScanAt: Date?
    private var scanTask: Task<Void, Never>?
    private var scheduleTimer: Timer?
    private var scheduledScanInProgress = false
    private var skippedScanPhases = Set<ScanPhase>()
    private var isReadyToPersistPreferences = false
    private var activationObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var preferencesSaveTask: Task<Void, Never>?
    private var streamedPaths = Set<String>()
    private var pendingStreamedItems: [CleanupItem] = []
    private var pendingStreamedSummary: ScanSummary?
    private var streamFlushTask: Task<Void, Never>?

    // Derived collections are cached because SwiftUI evaluates them many times
    // per render pass; caches invalidate whenever items/selection change.
    private var cachedSelectedItems: [CleanupItem]?
    private var cachedDuplicateGroups: [DuplicateReviewGroup]?
    private var cachedAppLeftoverGroups: [AppLeftoverGroup]?
    private var cachedCategoryTotals: [(category: CleanupCategory, bytes: Int64)]?

    private func invalidateDerivedCaches(selectionOnly: Bool) {
        cachedSelectedItems = nil
        guard !selectionOnly else { return }
        cachedDuplicateGroups = nil
        cachedAppLeftoverGroups = nil
        cachedCategoryTotals = nil
    }

    var selectedItems: [CleanupItem] {
        if let cachedSelectedItems { return cachedSelectedItems }
        let computed = items.filter { selectedIDs.contains($0.id) }
        cachedSelectedItems = computed
        return computed
    }

    var selectedBytes: Int64 {
        selectedItems.filter(\.canMoveToTrash).reduce(0) { $0 + $1.size }
    }

    var missingItemCount: Int {
        items.filter { !$0.existsOnDisk }.count
    }

    var categoryTotals: [(category: CleanupCategory, bytes: Int64)] {
        if let cachedCategoryTotals { return cachedCategoryTotals }
        let computed = Self.computeCategoryTotals(items: items)
        cachedCategoryTotals = computed
        return computed
    }

    private static func computeCategoryTotals(items: [CleanupItem]) -> [(category: CleanupCategory, bytes: Int64)] {
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

    var duplicateGroups: [DuplicateReviewGroup] {
        if let cachedDuplicateGroups { return cachedDuplicateGroups }
        let computed = Self.computeDuplicateGroups(items: items)
        cachedDuplicateGroups = computed
        return computed
    }

    private static func computeDuplicateGroups(items: [CleanupItem]) -> [DuplicateReviewGroup] {
        Dictionary(grouping: items.filter { $0.duplicateGroupID != nil }, by: { $0.duplicateGroupID ?? "" })
            .compactMap { groupID, groupItems in
                let existingItems = groupItems.filter(\.existsOnDisk)
                return existingItems.count > 1
                    ? DuplicateReviewGroup(id: groupID, items: existingItems.sorted { $0.path < $1.path })
                    : nil
            }
            .sorted {
                if $0.reclaimableBytes != $1.reclaimableBytes {
                    return $0.reclaimableBytes > $1.reclaimableBytes
                }
                return $0.name < $1.name
            }
    }

    var appLeftoverGroups: [AppLeftoverGroup] {
        if let cachedAppLeftoverGroups { return cachedAppLeftoverGroups }
        let computed = Self.computeAppLeftoverGroups(items: items)
        cachedAppLeftoverGroups = computed
        return computed
    }

    private static func computeAppLeftoverGroups(items: [CleanupItem]) -> [AppLeftoverGroup] {
        Dictionary(grouping: items.filter { $0.category == .appLeftovers && $0.relatedBundleID != nil }, by: { $0.relatedBundleID ?? "" })
            .compactMap { bundleID, groupItems in
                let existingItems = groupItems.filter(\.existsOnDisk)
                return existingItems.isEmpty
                    ? nil
                    : AppLeftoverGroup(id: bundleID, items: existingItems.sorted { $0.path < $1.path })
            }
            .sorted {
                if $0.totalBytes != $1.totalBytes {
                    return $0.totalBytes > $1.totalBytes
                }
                return $0.bundleID < $1.bundleID
            }
    }

    var lastScanDescription: String? {
        guard let lastScannedAt else { return nil }
        return Self.scanDateFormatter.string(from: lastScannedAt)
    }

    var staleStageEntries: [StageEntry] {
        stageEntries.filter { $0.existsInStage && $0.isStale(reminderAgeDays: stageReminderAgeDays) }
    }

    var nextScheduledScanDescription: String {
        guard scheduledScansEnabled else { return "Scheduled scans are off." }
        let baseDate = lastScheduledScanAt ?? Date()
        let nextDate = Calendar.current.date(byAdding: .day, value: scheduledScanIntervalDays, to: baseDate) ?? baseDate
        return "Next scheduled scan \(Self.scanDateFormatter.string(from: nextDate))."
    }

    init() {
        let preferences = ScanResultsStore.loadPreferences()
        options = preferences.options
        scanMode = preferences.scanMode
        savedScanProfiles = preferences.savedProfiles
        stageReminderAgeDays = preferences.stageReminderAgeDays
        showDirectTrashActions = preferences.showDirectTrashActions
        scheduledScansEnabled = preferences.scheduledScansEnabled
        scheduledScanIntervalDays = preferences.scheduledScanIntervalDays
        lastScheduledScanAt = preferences.lastScheduledScanAt
        showMenuBarExtra = preferences.showMenuBarExtra
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
        configureScheduleTimer()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshItemExistence()
            }
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.flushPendingPreferenceSave()
            }
        }
    }

    /// Re-stats every finding off the main thread and updates the cached
    /// `existsOnDisk` flags, so views never touch the filesystem during render.
    func refreshItemExistence() {
        let paths = items.map(\.path)
        guard !paths.isEmpty else { return }
        Task.detached(priority: .utility) { [weak self] in
            let missing = Set(paths.filter { !FileManager.default.fileExists(atPath: $0) })
            await self?.applyMissingPaths(missing)
        }
    }

    private func applyMissingPaths(_ missing: Set<String>) {
        var updated = items
        var changed = false
        for index in updated.indices {
            let exists = !missing.contains(updated[index].path)
            if updated[index].existsOnDisk != exists {
                updated[index].existsOnDisk = exists
                changed = true
            }
        }
        guard changed else { return }
        items = updated
        summary.reclaimableBytes = items.filter(\.canMoveToTrash).reduce(0) { $0 + $1.size }
    }

    func scan(isScheduled: Bool = false) {
        guard scanTask == nil else { return }
        scheduledScanInProgress = isScheduled
        selectedIDs.removeAll()
        lastDeletionMessage = nil
        items.removeAll()
        streamedPaths.removeAll()
        pendingStreamedItems.removeAll()
        pendingStreamedSummary = nil
        streamFlushTask?.cancel()
        streamFlushTask = nil
        summary = ScanSummary()
        scanProgress = ScanProgress()
        skippedScanPhases.removeAll()
        refreshFullDiskAccessStatus()
        refreshDiskSpace()
        state = .scanning("Preparing scan")

        scanTask = Task { [weak self] in
            guard let self else { return }
            let result = await scanner.scan(
                options: options,
                progress: { [weak self] progress in
                    guard let self, self.scanTask != nil else { return }
                    self.scanProgress = progress
                    self.state = .scanning(progress.message)
                },
                shouldSkipPhase: { [weak self] phase in
                    guard let self else { return false }
                    return self.skippedScanPhases.contains(phase)
                },
                onItem: { [weak self] item in
                    guard let self, self.scanTask != nil else { return }
                    self.appendStreamedItem(item)
                },
                onSummary: { [weak self] summary in
                    guard let self, self.scanTask != nil else { return }
                    self.pendingStreamedSummary = summary
                    self.scheduleStreamFlush()
                }
            )

            guard !Task.isCancelled else {
                self.flushStreamedItems()
                self.summary.reclaimableBytes = self.items.filter(\.canMoveToTrash).reduce(0) { $0 + $1.size }
                self.lastScannedAt = Date()
                ScanResultsStore.save(items: self.items, summary: self.summary)
                self.scanTask = nil
                self.state = .cancelled
                self.scanProgress = ScanProgress()
                self.scheduledScanInProgress = false
                return
            }

            streamFlushTask?.cancel()
            streamFlushTask = nil
            pendingStreamedItems.removeAll()
            items = result.items
            summary = result.summary
            lastScannedAt = Date()
            ScanResultsStore.save(items: items, summary: summary)
            refreshFullDiskAccessStatus()
            refreshDiskSpace()
            scanTask = nil
            scanProgress = ScanProgress()
            state = .finished
            if scheduledScanInProgress {
                lastScheduledScanAt = Date()
                savePreferences()
                sendScheduledScanNotification()
                scheduledScanInProgress = false
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    func skipCurrentScanPhase() {
        guard let phase = scanProgress.phase, isScanning else { return }
        skippedScanPhases.insert(phase)
        state = .scanning("Skipping \(phase.rawValue)")
    }

    func runScheduledScanNow() {
        guard !isScanning else { return }
        scan(isScheduled: true)
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

    func saveCurrentScanProfile(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        savedScanProfiles.removeAll { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
        savedScanProfiles.append(SavedScanProfile(name: name, options: options))
        savedScanProfiles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        lastDeletionMessage = "Saved scan profile \(name)."
    }

    func applySavedScanProfile(_ profile: SavedScanProfile) {
        options = profile.options
        scanMode = .custom
        lastDeletionMessage = "Applied scan profile \(profile.name)."
    }

    func deleteSavedScanProfile(_ profile: SavedScanProfile) {
        savedScanProfiles.removeAll { $0.id == profile.id }
        lastDeletionMessage = "Deleted scan profile \(profile.name)."
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

    func addCustomScanRoot(_ path: String) {
        let normalized = normalizedPath(path)
        guard !normalized.isEmpty, normalized != "/" else { return }
        guard !options.customScanRoots.contains(normalized) else { return }
        updateOptions { options in
            options.customScanRoots.append(normalized)
            options.customScanRoots.sort()
        }
        lastDeletionMessage = "Added \(normalized) to scanned folders."
    }

    func removeCustomScanRoot(_ path: String) {
        updateOptions { options in
            options.customScanRoots.removeAll { $0 == path }
        }
        lastDeletionMessage = "Removed scanned folder."
    }

    func excludeParentFolder(of item: CleanupItem) {
        addExcludedPath(item.url.deletingLastPathComponent().path)
        markCustomScanMode()
    }

    private func appendStreamedItem(_ item: CleanupItem) {
        guard streamedPaths.insert(item.path).inserted else { return }
        guard !isExcludedByPreferences(item.url) else { return }
        pendingStreamedItems.append(item)
        // Publish in batches so a fast scan doesn't force a SwiftUI diff per file.
        if pendingStreamedItems.count >= 200 {
            flushStreamedItems()
        } else {
            scheduleStreamFlush()
        }
    }

    private func scheduleStreamFlush() {
        guard streamFlushTask == nil else { return }
        streamFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self, !Task.isCancelled else { return }
            self.streamFlushTask = nil
            self.flushStreamedItems()
        }
    }

    private func flushStreamedItems() {
        if let pendingSummary = pendingStreamedSummary {
            summary.scannedFiles = pendingSummary.scannedFiles
            summary.skippedItems = pendingSummary.skippedItems
            summary.protectedLocationsBlocked = pendingSummary.protectedLocationsBlocked
            pendingStreamedSummary = nil
        }
        guard !pendingStreamedItems.isEmpty else { return }
        items.append(contentsOf: pendingStreamedItems)
        pendingStreamedItems.removeAll()
        if items.count > options.maxResults {
            items.sort { $0.size > $1.size }
            items.removeLast(items.count - options.maxResults)
        }
        summary.reclaimableBytes = items.lazy.filter(\.canMoveToTrash).reduce(0) { $0 + $1.size }
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
        refreshSnapshotCount()
        refreshTrashSize()
    }

    private func refreshTrashSize() {
        Task.detached(priority: .utility) { [weak self] in
            let fileManager = FileManager.default
            let trashURL = fileManager.urls(for: .trashDirectory, in: .userDomainMask).first
                ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
            var total: Int64 = 0
            let keys: [URLResourceKey] = [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
            if let enumerator = fileManager.enumerator(
                at: trashURL,
                includingPropertiesForKeys: keys,
                options: [],
                errorHandler: { _, _ in true }
            ) {
                while let url = enumerator.nextObject() as? URL {
                    guard let values = try? url.resourceValues(forKeys: Set(keys)),
                          values.isRegularFile == true else { continue }
                    total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                }
            }
            let bytes = total
            await MainActor.run { [weak self] in
                self?.trashBytes = bytes
            }
        }
    }

    private func refreshSnapshotCount() {
        Task { [weak self] in
            let count = await SnapshotService.localSnapshotCount()
            self?.localSnapshotCount = count
        }
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

    func selectAppLeftoverGroup(_ group: AppLeftoverGroup) {
        let selectable = group.items.filter(\.canMoveToTrash)
        selectedIDs.formUnion(selectable.map(\.id))
        lastDeletionMessage = "Selected \(selectable.count) leftover item\(selectable.count == 1 ? "" : "s") for \(group.bundleID)."
    }

    func selectDuplicates(in group: DuplicateReviewGroup, keeping strategy: DuplicateKeepStrategy) {
        guard let keeper = duplicateKeeper(in: group, strategy: strategy) else { return }
        let groupIDs = Set(group.items.map(\.id))
        selectedIDs.subtract(groupIDs)
        let removableIDs = group.items
            .filter { $0.id != keeper.id && $0.canMoveToTrash }
            .map(\.id)
        selectedIDs.formUnion(removableIDs)
        lastDeletionMessage = "Selected \(removableIDs.count) duplicate item\(removableIDs.count == 1 ? "" : "s"); keeping \(keeper.name)."
    }

    func clearDuplicateSelection(in group: DuplicateReviewGroup) {
        selectedIDs.subtract(group.items.map(\.id))
    }

    func clearSelection() {
        selectedIDs.removeAll()
    }

    func exportFindings(_ findings: [CleanupItem], format: FindingsExportFormat) {
        if let message = FindingsExporter.promptAndExport(items: findings, format: format) {
            lastDeletionMessage = message
        }
    }

    func reveal(_ item: CleanupItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func showDetails(for item: CleanupItem) {
        detailItem = item
    }

    func removeMissingItems() {
        var updated = items
        for index in updated.indices {
            updated[index].existsOnDisk = FileManager.default.fileExists(atPath: updated[index].path)
        }
        updated.removeAll { !$0.existsOnDisk }
        items = updated
        selectedIDs = selectedIDs.intersection(Set(items.map(\.id)))
        summary.reclaimableBytes = items.filter(\.canMoveToTrash).reduce(0) { $0 + $1.size }
        ScanResultsStore.save(items: items, summary: summary)
        refreshDiskSpace()
    }

    func moveSelectedToTrash() {
        moveToTrash(selectedItems.filter(\.canMoveToTrash))
    }

    func moveToTrash(_ requested: [CleanupItem]) {
        let targets = requested.filter(\.canMoveToTrash)
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
            registerUndo(actionName: "Move to Trash") { manager in
                for entry in newHistory {
                    manager.restoreFromTrash(entry)
                }
            }
        }
        lastDeletionMessage = failed == 0
            ? "Moved \(removed) item\(removed == 1 ? "" : "s") to Trash."
            : "Moved \(removed) item\(removed == 1 ? "" : "s") to Trash. \(failed) failed."
        ScanResultsStore.save(items: items, summary: summary)
        refreshDiskSpace()
    }

    func moveSelectedToStage() {
        moveToStage(selectedItems.filter(\.canMoveToTrash))
    }

    func moveToStage(_ requested: [CleanupItem]) {
        let targets = requested.filter(\.canMoveToTrash)
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
            registerUndo(actionName: "Move to Stage") { manager in
                for entry in newEntries {
                    manager.restoreFromStage(entry)
                }
            }
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
                let historyEntry = TrashHistoryEntry(
                    itemName: entry.itemName,
                    originalURL: entry.originalURL,
                    trashedURL: resultingURL,
                    size: entry.size,
                    movedAt: Date()
                )
                trashHistory.insert(historyEntry, at: 0)
                trashHistory = Array(trashHistory.prefix(100))
                ScanResultsStore.saveTrashHistory(trashHistory)
                registerUndo(actionName: "Move to Trash") { manager in
                    manager.restoreFromTrash(historyEntry)
                }
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

    func moveStaleStageEntriesToTrash() {
        let targets = staleStageEntries
        guard !targets.isEmpty else { return }

        var moved = 0
        var failed = 0
        var newHistory: [TrashHistoryEntry] = []

        for entry in targets {
            do {
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: entry.stagedURL, resultingItemURL: &resultingURL)
                if let resultingURL = resultingURL as URL? {
                    newHistory.append(TrashHistoryEntry(
                        itemName: entry.itemName,
                        originalURL: entry.originalURL,
                        trashedURL: resultingURL,
                        size: entry.size,
                        movedAt: Date()
                    ))
                }
                removeStageContainerIfEmpty(for: entry)
                stageEntries.removeAll { $0.id == entry.id }
                moved += 1
            } catch {
                failed += 1
            }
        }

        if !newHistory.isEmpty {
            trashHistory.insert(contentsOf: newHistory, at: 0)
            trashHistory = Array(trashHistory.prefix(100))
            ScanResultsStore.saveTrashHistory(trashHistory)
        }
        ScanResultsStore.saveStageEntries(stageEntries)
        lastDeletionMessage = failed == 0
            ? "Moved \(moved) stale staged item\(moved == 1 ? "" : "s") to Trash."
            : "Moved \(moved) stale staged item\(moved == 1 ? "" : "s") to Trash. \(failed) failed."
        refreshDiskSpace()
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

    func revealStagedItem(_ entry: StageEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([entry.stagedURL])
    }

    func revealOriginalLocation(for entry: StageEntry) {
        if FileManager.default.fileExists(atPath: entry.originalURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([entry.originalURL])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([entry.originalURL.deletingLastPathComponent()])
        }
    }

    /// Registers an undo operation on the key window's undo manager so that
    /// Edit > Undo (Cmd+Z) reverses the last cleanup action.
    private func registerUndo(actionName: String, handler: @escaping (CleanupManager) -> Void) {
        guard let undoManager = NSApp.keyWindow?.undoManager ?? NSApp.mainWindow?.undoManager else { return }
        undoManager.registerUndo(withTarget: self) { manager in
            handler(manager)
        }
        undoManager.setActionName(actionName)
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
        // Debounced: Settings steppers/toggles fire didSet per tick; one write
        // shortly after the last change is enough.
        preferencesSaveTask?.cancel()
        preferencesSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, !Task.isCancelled else { return }
            self.preferencesSaveTask = nil
            self.writePreferencesNow()
        }
    }

    private func flushPendingPreferenceSave() {
        guard preferencesSaveTask != nil else { return }
        preferencesSaveTask?.cancel()
        preferencesSaveTask = nil
        writePreferencesNow()
    }

    private func writePreferencesNow() {
        ScanResultsStore.savePreferences(CleanupPreferences(
            scanMode: scanMode,
            options: options,
            savedProfiles: savedScanProfiles,
            stageReminderAgeDays: stageReminderAgeDays,
            showDirectTrashActions: showDirectTrashActions,
            scheduledScansEnabled: scheduledScansEnabled,
            scheduledScanIntervalDays: scheduledScanIntervalDays,
            lastScheduledScanAt: lastScheduledScanAt,
            showMenuBarExtra: showMenuBarExtra
        ))
    }

    private func configureScheduleTimer() {
        scheduleTimer?.invalidate()
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.runScheduledScanIfDue()
            }
        }
    }

    private func runScheduledScanIfDue() {
        guard scheduledScansEnabled, !isScanning else { return }
        guard let lastScheduledScanAt else {
            self.lastScheduledScanAt = Date()
            savePreferences()
            return
        }

        let nextDate = Calendar.current.date(byAdding: .day, value: scheduledScanIntervalDays, to: lastScheduledScanAt) ?? lastScheduledScanAt
        guard Date() >= nextDate else { return }
        scan(isScheduled: true)
    }

    private func requestNotificationAuthorization() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }

    private func sendScheduledScanNotification() {
        let content = UNMutableNotificationContent()
        content.title = "MClean scheduled scan complete"
        content.body = "\(items.count) findings, \(ByteCount.string(summary.reclaimableBytes)) potential cleanup. Review is manual."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "mclean.scheduled-scan.\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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

    private func duplicateKeeper(in group: DuplicateReviewGroup, strategy: DuplicateKeepStrategy) -> CleanupItem? {
        switch strategy {
        case .newest:
            return group.items.max { lhs, rhs in
                (lhs.modifiedAt ?? .distantPast) < (rhs.modifiedAt ?? .distantPast)
            }
        case .oldest:
            return group.items.min { lhs, rhs in
                (lhs.modifiedAt ?? .distantFuture) < (rhs.modifiedAt ?? .distantFuture)
            }
        case .originalFolder:
            return group.items.sorted { lhs, rhs in
                let lhsRank = originalFolderRank(lhs)
                let rhsRank = originalFolderRank(rhs)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.path.count < rhs.path.count
            }.first
        case .shortestPath:
            return group.items.min { lhs, rhs in
                if lhs.path.count != rhs.path.count { return lhs.path.count < rhs.path.count }
                return lhs.path < rhs.path
            }
        }
    }

    private func originalFolderRank(_ item: CleanupItem) -> Int {
        let path = item.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix("\(home)/Documents") { return 0 }
        if path.hasPrefix("\(home)/Desktop") { return 1 }
        if path.hasPrefix("\(home)/Pictures") { return 2 }
        if path.hasPrefix("\(home)/Movies") { return 3 }
        if path.hasPrefix("\(home)/Music") { return 4 }
        if path.hasPrefix("\(home)/Downloads") { return 8 }
        return 5
    }

    private static let scanDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
