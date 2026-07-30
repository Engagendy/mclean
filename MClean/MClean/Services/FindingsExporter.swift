import AppKit
import Foundation
import UniformTypeIdentifiers

enum FindingsExportFormat: String, CaseIterable, Identifiable {
    case csv = "CSV"
    case json = "JSON"

    var id: String { rawValue }

    var contentType: UTType {
        switch self {
        case .csv: return .commaSeparatedText
        case .json: return .json
        }
    }

    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .json: return "json"
        }
    }
}

enum FindingsExporter {
    @MainActor
    static func promptAndExport(items: [CleanupItem], format: FindingsExportFormat) -> String? {
        guard !items.isEmpty else { return nil }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultFileName(format: format)
        panel.title = "Export Findings"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        do {
            let data: Data
            switch format {
            case .csv:
                data = csvData(items: items)
            case .json:
                data = try jsonData(items: items)
            }
            try data.write(to: url, options: [.atomic])
            return "Exported \(items.count) finding\(items.count == 1 ? "" : "s") to \(url.lastPathComponent)."
        } catch {
            return "Could not export findings: \(error.localizedDescription)"
        }
    }

    static func csvData(items: [CleanupItem]) -> Data {
        var lines = ["Name,Path,Size (Bytes),Size,Category,Risk,Protection,Source,Reason,Modified,Exists"]
        let dateFormatter = ISO8601DateFormatter()
        for item in items {
            let fields = [
                item.name,
                item.path,
                "\(item.size)",
                ByteCount.string(item.size),
                item.category.rawValue,
                item.risk.rawValue,
                item.protection.rawValue,
                item.sourceName ?? item.resolvedSourceKind.rawValue,
                item.reason,
                item.modifiedAt.map(dateFormatter.string(from:)) ?? "",
                item.existsOnDisk ? "yes" : "no"
            ]
            lines.append(fields.map(escapeCSVField).joined(separator: ","))
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    static func jsonData(items: [CleanupItem]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(items)
    }

    private static func escapeCSVField(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func defaultFileName(format: FindingsExportFormat) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "MClean Findings \(formatter.string(from: Date())).\(format.fileExtension)"
    }
}
