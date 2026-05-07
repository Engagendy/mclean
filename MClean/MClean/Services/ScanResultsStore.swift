import Foundation

enum ScanResultsStore {
    private static let fileName = "last-scan-results.json"
    private static let historyFileName = "trash-history.json"
    private static let stageFileName = "stage-items.json"
    private static let preferencesFileName = "preferences.json"

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

    static func stageDirectory() throws -> URL {
        let directory = try appSupportDirectory()
            .appendingPathComponent("Stage", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
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

    static func saveStageEntries(_ entries: [StageEntry]) {
        do {
            let directory = try appSupportDirectory()
            let url = directory.appendingPathComponent(stageFileName)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Best-effort cache; staged files remain in the Stage folder.
        }
    }

    static func loadStageEntries() -> [StageEntry] {
        do {
            let url = try appSupportDirectory().appendingPathComponent(stageFileName)
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([StageEntry].self, from: data)
        } catch {
            return []
        }
    }

    static func savePreferences(_ preferences: CleanupPreferences) {
        do {
            let url = try appSupportDirectory().appendingPathComponent(preferencesFileName)
            let data = try JSONEncoder().encode(preferences)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Preferences fall back to defaults when persistence is unavailable.
        }
    }

    static func loadPreferences() -> CleanupPreferences {
        do {
            let url = try appSupportDirectory().appendingPathComponent(preferencesFileName)
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(CleanupPreferences.self, from: data)
        } catch {
            return CleanupPreferences()
        }
    }
}

struct CleanupPreferences: Codable, Equatable {
    var scanMode: ScanMode = .quick
    var options = ScanOptions()
}
