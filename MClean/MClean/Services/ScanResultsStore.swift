import Foundation

enum ScanResultsStore {
    private static let fileName = "last-scan-results.json"
    private static let historyFileName = "trash-history.json"

    static func load() -> StoredScanResults? {
        guard let url = try? appSupportDirectory().appendingPathComponent(fileName) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(StoredScanResults.self, from: data)
    }

    static func save(items: [CleanupItem], summary: ScanSummary) {
        let payload = StoredScanResults(scannedAt: Date(), items: items, summary: summary)

        do {
            let url = try appSupportDirectory().appendingPathComponent(fileName)
            let data = try JSONEncoder().encode(payload)
            try data.write(to: url, options: [.atomic])
        } catch {
            return
        }
    }

    private static func appSupportDirectory() throws -> URL {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directory = base
            .appendingPathComponent("MClean", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func saveTrashHistory(_ history: [TrashHistoryEntry]) {
        do {
            let directory = try appSupportDirectory()
            let url = directory.appendingPathComponent(historyFileName)
            let data = try JSONEncoder().encode(history)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Best-effort cache; the app can continue without history persistence.
        }
    }

    static func loadTrashHistory() -> [TrashHistoryEntry] {
        do {
            let url = try appSupportDirectory().appendingPathComponent(historyFileName)
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([TrashHistoryEntry].self, from: data)
        } catch {
            return []
        }
    }
}
