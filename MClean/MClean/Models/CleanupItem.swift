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

enum CleanupSourceKind: String, CaseIterable, Identifiable, Codable {
    case general = "General"
    case browser = "Browser"
    case developer = "Developer"
    case appLeftover = "App Leftover"
    case duplicate = "Duplicate"
    case system = "System"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .general: return "folder"
        case .browser: return "globe"
        case .developer: return "hammer"
        case .appLeftover: return "app.badge"
        case .duplicate: return "doc.on.doc"
        case .system: return "lock.shield"
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
    var sourceKind: CleanupSourceKind?
    var sourceName: String?
    var sourceWarning: String?

    var path: String { url.path }
    var existsOnDisk: Bool { FileManager.default.fileExists(atPath: path) }
    var resolvedSourceKind: CleanupSourceKind {
        sourceKind ?? Self.defaultSourceKind(for: category)
    }
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
        relatedBundleID: String? = nil,
        sourceKind: CleanupSourceKind? = nil,
        sourceName: String? = nil,
        sourceWarning: String? = nil
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
        self.sourceKind = sourceKind
        self.sourceName = sourceName
        self.sourceWarning = sourceWarning
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
        case sourceKind
        case sourceName
        case sourceWarning
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
        sourceKind = try container.decodeIfPresent(CleanupSourceKind.self, forKey: .sourceKind)
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName)
        sourceWarning = try container.decodeIfPresent(String.self, forKey: .sourceWarning)
    }

    static func defaultSourceKind(for category: CleanupCategory) -> CleanupSourceKind {
        switch category {
        case .developerData:
            return .developer
        case .appLeftovers:
            return .appLeftover
        case .duplicates:
            return .duplicate
        case .systemStorage:
            return .system
        default:
            return .general
        }
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

struct DuplicateReviewGroup: Identifiable, Hashable {
    let id: String
    let items: [CleanupItem]

    var duplicateCount: Int { items.count }
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.size } }
    var reclaimableBytes: Int64 {
        max(Int64(items.count - 1), 0) * representativeSize
    }
    var representativeSize: Int64 { items.first?.size ?? 0 }
    var name: String { items.first?.name ?? "Duplicate Group" }
}

enum DuplicateKeepStrategy: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case oldest = "Oldest"
    case originalFolder = "Original Folder"
    case shortestPath = "Shortest Path"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .newest: return "calendar.badge.clock"
        case .oldest: return "archivebox"
        case .originalFolder: return "folder"
        case .shortestPath: return "arrow.down.right.and.arrow.up.left"
        }
    }
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

struct StageEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    let itemName: String
    let originalURL: URL
    let stagedURL: URL
    let size: Int64
    let category: CleanupCategory
    let reason: String
    let stagedAt: Date

    var canRestore: Bool {
        FileManager.default.fileExists(atPath: stagedURL.path) &&
            !FileManager.default.fileExists(atPath: originalURL.path)
    }

    var existsInStage: Bool {
        FileManager.default.fileExists(atPath: stagedURL.path)
    }
}

struct DiskSpaceSnapshot: Equatable {
    var totalBytes: Int64 = 0
    var freeBytes: Int64 = 0

    var usedBytes: Int64 {
        max(totalBytes - freeBytes, 0)
    }

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }
}

enum ScanState: Equatable {
    case idle
    case scanning(String)
    case finished
    case cancelled
    case failed(String)
}

enum ScanMode: String, CaseIterable, Identifiable, Codable {
    case quick = "Quick"
    case deep = "Deep"
    case developer = "Developer"
    case downloadsReview = "Downloads Review"
    case custom = "Custom"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .quick:
            return "Fast scan for common cleanup locations."
        case .deep:
            return "Broader scan, including app support and protected storage."
        case .developer:
            return "Focused scan for build products, simulators, package caches, and tool data."
        case .downloadsReview:
            return "Focused review of downloaded, old, large, and duplicate files."
        case .custom:
            return "Use the selected scan options."
        }
    }

    var includedSummary: String {
        switch self {
        case .quick:
            return "Caches, Downloads, Temporary, Large Files, Duplicates, Developer Data, App Leftovers"
        case .deep:
            return "Quick scan plus Old Files, Browser Caches, App Support, and System Storage"
        case .developer:
            return "Developer Data only"
        case .downloadsReview:
            return "Downloads, Large Files, Duplicates, and Old Files"
        case .custom:
            return "Uses the category toggles currently selected"
        }
    }
}
