import Darwin
import Foundation

enum MCleanCLI {
    static var shouldRun: Bool {
        CommandLine.arguments.contains("--cli-scan") || CommandLine.arguments.contains("--cli-help")
    }

    static func runAndExit() {
        if CommandLine.arguments.contains("--cli-help") {
            print(helpText)
            exit(0)
        }

        let state = CLIRunState()
        Task {
            do {
                let report = await makeReport(arguments: CommandLine.arguments)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(report)
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            } catch {
                FileHandle.standardError.write(Data("MClean CLI failed: \(error.localizedDescription)\n".utf8))
                state.exitCode = 1
            }
            state.completed = true
        }

        while !state.completed {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        exit(state.exitCode)
    }

    private static func makeReport(arguments: [String]) async -> CLIReport {
        let profile = profileArgument(in: arguments)
        var options = options(for: profile)
        if let maxResults = intArgument("--max-results", in: arguments) {
            options.maxResults = max(1, maxResults)
        }

        let scanner = FileScanner()
        let result = await scanner.scan(
            options: options,
            progress: { _ in },
            shouldSkipPhase: { _ in false },
            onItem: { _ in },
            onSummary: { _ in }
        )

        return CLIReport(
            generatedAt: Date(),
            profile: profile.rawValue,
            summary: result.summary,
            items: result.items.map(CLIItem.init(item:))
        )
    }

    private static func profileArgument(in arguments: [String]) -> ScanMode {
        guard let value = stringArgument("--profile", in: arguments)?.lowercased() else { return .quick }
        switch value {
        case "quick": return .quick
        case "deep": return .deep
        case "developer": return .developer
        case "downloads", "downloads-review": return .downloadsReview
        default: return .quick
        }
    }

    private static func options(for profile: ScanMode) -> ScanOptions {
        var options = ScanOptions()
        switch profile {
        case .quick, .custom:
            options.includeOldFiles = false
            options.includeBrowserCaches = false
            options.includeAppSupport = false
            options.includeSystemStorage = false
        case .deep:
            options.includeOldFiles = true
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
        }
        return options
    }

    private static func stringArgument(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name),
              arguments.indices.contains(arguments.index(after: index)) else { return nil }
        return arguments[arguments.index(after: index)]
    }

    private static func intArgument(_ name: String, in arguments: [String]) -> Int? {
        stringArgument(name, in: arguments).flatMap(Int.init)
    }

    private static let helpText = """
    MClean CLI scan mode

    Usage:
      MClean --cli-scan [--profile quick|deep|developer|downloads-review] [--max-results N]

    The CLI only scans and writes JSON. It never stages, trashes, or deletes files.
    """
}

private final class CLIRunState {
    var completed = false
    var exitCode: Int32 = 0
}

private struct CLIReport: Codable {
    let generatedAt: Date
    let profile: String
    let summary: ScanSummary
    let items: [CLIItem]
}

private struct CLIItem: Codable {
    let path: String
    let name: String
    let size: Int64
    let modifiedAt: Date?
    let category: CleanupCategory
    let risk: CleanupRisk
    let reason: String
    let isDirectory: Bool
    let protection: CleanupProtection
    let sourceKind: CleanupSourceKind
    let sourceName: String?
    let sourceWarning: String?
    let relatedBundleID: String?
    let duplicateGroupID: String?
    let duplicateCount: Int?

    init(item: CleanupItem) {
        path = item.path
        name = item.name
        size = item.size
        modifiedAt = item.modifiedAt
        category = item.category
        risk = item.risk
        reason = item.reason
        isDirectory = item.isDirectory
        protection = item.protection
        sourceKind = item.resolvedSourceKind
        sourceName = item.sourceName
        sourceWarning = item.sourceWarning
        relatedBundleID = item.relatedBundleID
        duplicateGroupID = item.duplicateGroupID
        duplicateCount = item.duplicateCount
    }
}
