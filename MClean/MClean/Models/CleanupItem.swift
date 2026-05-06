import Foundation

enum CleanupCategory: String, CaseIterable, Identifiable, Codable {
    case largeFiles = "Large Files"
    case caches = "Caches"
    case downloads = "Downloads"
    case temporary = "Temporary"
    case oldFiles = "Old Files"
    case developerData = "Developer Data"
    case appSupport = "App Support"
    case systemStorage = "System Storage"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .largeFiles: return "doc.text"
        case .caches: return "shippingbox"
        case .downloads: return "arrow.down.circle"
        case .temporary: return "clock.arrow.circlepath"
        case .oldFiles: return "archivebox"
        case .developerData: return "hammer"
        case .appSupport: return "app"
        case .systemStorage: return "lock.shield"
        }
    }
}

enum CleanupRisk: String, CaseIterable, Codable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var sortRank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    var explanation: String {
        switch self {
        case .low:
            return "Usually safe to remove. The app moves it to Trash first."
        case .medium:
            return "Review before removing. This may include downloads, large files, or developer data."
        case .high:
            return "Review in Finder first. This may include personal data or app-managed storage."
        }
    }
}

struct CleanupItem: Identifiable, Hashable, Codable {
    var id = UUID()
    let url: URL
    let name: String
    let size: Int64
    let modifiedAt: Date?
    let category: CleanupCategory
    let risk: CleanupRisk
    let reason: String
    let isDirectory: Bool

    var path: String { url.path }
    var existsOnDisk: Bool { FileManager.default.fileExists(atPath: path) }
    var isRecommendedForCleanup: Bool {
        existsOnDisk && risk != .high && category != .appSupport && category != .systemStorage
    }
}

struct ScanSummary: Codable {
    var scannedFiles: Int = 0
    var skippedItems: Int = 0
    var reclaimableBytes: Int64 = 0
    var protectedLocationsBlocked: Int = 0
}

struct StoredScanResults: Codable {
    let scannedAt: Date
    let items: [CleanupItem]
    let summary: ScanSummary
}

enum ScanState: Equatable {
    case idle
    case scanning(String)
    case finished
    case cancelled
    case failed(String)
}

enum ScanMode: String, CaseIterable, Identifiable {
    case quick = "Quick"
    case deep = "Deep"
    case custom = "Custom"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .quick:
            return "Fast scan for common cleanup locations."
        case .deep:
            return "Broader scan, including app support and protected storage."
        case .custom:
            return "Use the selected scan options."
        }
    }
}
