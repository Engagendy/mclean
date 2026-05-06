import Foundation

enum ScanResultsStore {
    private static let fileName = "last-scan-results.json"

    static func load() -> StoredScanResults? {
        guard let url = storeURL else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(StoredScanResults.self, from: data)
    }

    static func save(items: [CleanupItem], summary: ScanSummary) {
        guard let url = storeURL else { return }
        let payload = StoredScanResults(scannedAt: Date(), items: items, summary: summary)

        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(payload)
            try data.write(to: url, options: [.atomic])
        } catch {
            return
        }
    }

    private static var storeURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base
            .appendingPathComponent("MClean", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
