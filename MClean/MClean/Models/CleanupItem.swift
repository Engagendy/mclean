import Foundation

enum CleanupCategory: String, CaseIterable, Identifiable, Codable {
    case largeFiles = "Large Files"
    case duplicates = "Duplicates"
    case caches = "Caches"
    case downloads = "Downloads"
    case temporary = "Temporary"
    case oldFiles = "Old Files"
    case developerData = "Developer Data"
    case appLeftovers = "App Leftovers"
    case appSupport = "App Support"
    case systemStorage = "System Storage"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .largeFiles: return "doc.text"
        case .duplicates: return "doc.on.doc"
        case .caches: return "shippingbox"
        case .downloads: return "arrow.down.circle"
        case .temporary: return "clock.arrow.circlepath"
        case .oldFiles: return "archivebox"
        case .developerData: return "hammer"
        case .appLeftovers: return "app.badge"
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

enum CleanupProtection: String, CaseIterable, Codable {
    case normal = "Normal"
    case reviewOnly = "Review"
    case neverDelete = "Never Delete"

    var sortRank: Int {
        switch self {
        case .normal: return 0
        case .reviewOnly: return 1
        case .neverDelete: return 2
        }
    }

    var explanation: String {
        switch self {
        case .normal:
            return "Can be moved to Trash after review."
        case .reviewOnly:
            return "Review carefully before moving to Trash."
        case .neverDelete:
            return "MClean will not move this item to Trash."
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
    var protection: CleanupProtection = .normal
    var duplicateGroupID: String?
    var duplicateCount: Int?
    var relatedBundleID: String?

    var path: String { url.path }
    var existsOnDisk: Bool { FileManager.default.fileExists(atPath: path) }
    var canMoveToTrash: Bool { existsOnDisk && protection != .neverDelete }
    var isRecommendedForCleanup: Bool {
        canMoveToTrash && risk != .high && protection == .normal && category != .appSupport && category != .systemStorage
    }

    init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        size: Int64,
        modifiedAt: Date?,
        category: CleanupCategory,
        risk: CleanupRisk,
        reason: String,
        isDirectory: Bool,
        protection: CleanupProtection = .normal,
        duplicateGroupID: String? = nil,
        duplicateCount: Int? = nil,
        relatedBundleID: String? = nil
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.size = size
        self.modifiedAt = modifiedAt
        self.category = category
        self.risk = risk
        self.reason = reason
        self.isDirectory = isDirectory
        self.protection = protection
        self.duplicateGroupID = duplicateGroupID
        self.duplicateCount = duplicateCount
        self.relatedBundleID = relatedBundleID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case url
        case name
        case size
        case modifiedAt
        case category
        case risk
        case reason
        case isDirectory
        case protection
        case duplicateGroupID
        case duplicateCount
        case relatedBundleID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        url = try container.decode(URL.self, forKey: .url)
        name = try container.decode(String.self, forKey: .name)
        size = try container.decode(Int64.self, forKey: .size)
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt)
        category = try container.decode(CleanupCategory.self, forKey: .category)
        risk = try container.decode(CleanupRisk.self, forKey: .risk)
        reason = try container.decode(String.self, forKey: .reason)
        isDirectory = try container.decode(Bool.self, forKey: .isDirectory)
        protection = try container.decodeIfPresent(CleanupProtection.self, forKey: .protection) ?? .normal
        duplicateGroupID = try container.decodeIfPresent(String.self, forKey: .duplicateGroupID)
        duplicateCount = try container.decodeIfPresent(Int.self, forKey: .duplicateCount)
        relatedBundleID = try container.decodeIfPresent(String.self, forKey: .relatedBundleID)
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

struct TrashHistoryEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    let itemName: String
    let originalURL: URL
    let trashedURL: URL
    let size: Int64
    let movedAt: Date

    var canRestore: Bool {
        FileManager.default.fileExists(atPath: trashedURL.path) &&
            !FileManager.default.fileExists(atPath: originalURL.path)
    }
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
