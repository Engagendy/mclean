import AppKit
import SwiftUI

struct ResultsTable: View {
    @EnvironmentObject private var manager: CleanupManager
    let items: [CleanupItem]
    @State private var sortOrder = [KeyPathComparator(\CleanupItem.size, order: .reverse)]

    private var sortedItems: [CleanupItem] {
        items.sorted(using: sortOrder)
    }

    private var selectionBinding: Binding<Set<CleanupItem.ID>> {
        Binding(
            get: { manager.selectedIDs },
            set: { ids in
                let movableIDs = Set(manager.items.filter(\.canMoveToTrash).map(\.id))
                manager.selectedIDs = ids.intersection(movableIDs)
            }
        )
    }

    var body: some View {
        Table(sortedItems, selection: selectionBinding, sortOrder: $sortOrder) {
            TableColumn("") { item in
                Toggle("", isOn: Binding(
                    get: { manager.selectedIDs.contains(item.id) },
                    set: { _ in manager.toggleSelection(for: item) }
                ))
                .labelsHidden()
                .disabled(!item.canMoveToTrash)
            }
            .width(34)

            TableColumn("Name", value: \.name) { item in
                HStack {
                    Image(systemName: item.isDirectory ? "folder" : "doc")
                        .foregroundStyle(item.isDirectory ? .blue : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .lineLimit(1)
                        Text(item.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .contextMenu {
                    Button {
                        manager.reveal(item)
                    } label: {
                        Label("Reveal in Finder", systemImage: "finder")
                    }
                    .disabled(!item.existsOnDisk)

                    Button {
                        copyPath(item.path)
                    } label: {
                        Label("Copy Path", systemImage: "doc.on.doc")
                    }

                    Button {
                        manager.excludeParentFolder(of: item)
                    } label: {
                        Label("Exclude Parent Folder", systemImage: "folder.badge.minus")
                    }
                    .disabled(!item.existsOnDisk)
                }
            }
            .width(min: 280, ideal: 420)

            TableColumn("Size", value: \.size) { item in
                Text(ByteCount.string(item.size))
                    .monospacedDigit()
            }
            .width(110)

            TableColumn("Category", value: \.category.rawValue) { item in
                Label(item.category.rawValue, systemImage: item.category.symbolName)
            }
            .width(150)

            TableColumn("Risk") { item in
                RiskBadge(risk: item.risk)
            }
            .width(90)

            TableColumn("Protection") { item in
                ProtectionBadge(protection: item.protection)
            }
            .width(120)

            TableColumn("Source") { item in
                Label(item.sourceName ?? item.resolvedSourceKind.rawValue, systemImage: item.resolvedSourceKind.symbolName)
                    .lineLimit(1)
            }
            .width(160)

            TableColumn("Status") { item in
                if item.existsOnDisk {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.reason)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let duplicateCount = item.duplicateCount {
                            Text("\(duplicateCount) duplicate matches")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Label("Missing", systemImage: "questionmark.folder")
                        .foregroundStyle(.red)
                }
            }
            .width(min: 130, ideal: 180)

            TableColumn("Modified") { item in
                Text(item.modifiedAt.map(Self.dateFormatter.string(from:)) ?? "-")
                    .foregroundStyle(.secondary)
            }
            .width(110)

            TableColumn("") { item in
                HStack(spacing: 8) {
                    Button {
                        manager.showDetails(for: item)
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .help("Show Details")

                    Button {
                        manager.reveal(item)
                    } label: {
                        Image(systemName: "finder")
                    }
                    .help("Reveal in Finder")
                }
            }
            .width(74)
        }
        .opacity(items.contains(where: { !$0.existsOnDisk }) ? 0.98 : 1)
        .overlay {
            if isScanning && items.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Scanning your Mac")
                        .font(.headline)
                    Text(scanMessage)
                        .foregroundStyle(.secondary)
                }
            } else if items.isEmpty {
                ContentUnavailableView("Ready to Scan", systemImage: "sparkle.magnifyingglass", description: Text("Choose scan options in the sidebar, then click Scan. Previous results will appear here when available."))
            }
        }
    }

    private var isScanning: Bool {
        if case .scanning = manager.state { return true }
        return false
    }

    private var scanMessage: String {
        if case .scanning(let message) = manager.state {
            return message
        }
        return "Preparing scan"
    }

    private func copyPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

struct ProtectionBadge: View {
    let protection: CleanupProtection

    var body: some View {
        Label(protection.rawValue, systemImage: symbolName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private var symbolName: String {
        switch protection {
        case .normal: return "checkmark.shield"
        case .reviewOnly: return "eye"
        case .neverDelete: return "lock.shield"
        }
    }

    private var color: Color {
        switch protection {
        case .normal: return .green
        case .reviewOnly: return .orange
        case .neverDelete: return .red
        }
    }
}

struct FileDetailsView: View {
    @EnvironmentObject private var manager: CleanupManager
    let item: CleanupItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: item.isDirectory ? "folder" : "doc")
                    .font(.largeTitle)
                    .foregroundStyle(item.isDirectory ? .blue : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                    Text(item.path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(20)

            Divider()

            Form {
                LabeledContent("Size", value: ByteCount.string(item.size))
                LabeledContent("Category", value: item.category.rawValue)
                LabeledContent("Risk") {
                    RiskBadge(risk: item.risk)
                }
                LabeledContent("Protection") {
                    ProtectionBadge(protection: item.protection)
                }
                LabeledContent("Status", value: item.existsOnDisk ? "Exists on disk" : "Missing")
                LabeledContent("Reason", value: item.reason)
                LabeledContent("Modified", value: item.modifiedAt.map(Self.dateFormatter.string(from:)) ?? "-")
                if let duplicateGroupID = item.duplicateGroupID {
                    LabeledContent("Duplicate Group", value: duplicateGroupID)
                }
                if let duplicateCount = item.duplicateCount {
                    LabeledContent("Duplicate Matches", value: "\(duplicateCount)")
                }
                if let relatedBundleID = item.relatedBundleID {
                    LabeledContent("Related Bundle ID", value: relatedBundleID)
                }
                LabeledContent("Source") {
                    Label(item.sourceName ?? item.resolvedSourceKind.rawValue, systemImage: item.resolvedSourceKind.symbolName)
                }
                if let sourceWarning = item.sourceWarning {
                    LabeledContent("Source Warning") {
                        Text(sourceWarning)
                            .foregroundStyle(.orange)
                    }
                }
                LabeledContent("Safety") {
                    Text(item.protection.explanation)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button {
                    manager.reveal(item)
                } label: {
                    Label("Reveal in Finder", systemImage: "finder")
                }
                .disabled(!item.existsOnDisk)

                Button {
                    NSWorkspace.shared.open(item.url)
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.app")
                }
                .disabled(!item.existsOnDisk)

                Spacer()

                Button("Close") {
                    manager.detailItem = nil
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(20)
        }
        .frame(minWidth: 640, minHeight: 520)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

struct RiskBadge: View {
    let risk: CleanupRisk

    var body: some View {
        Text(risk.rawValue)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch risk {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}
