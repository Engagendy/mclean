import SwiftUI

struct ResultsTable: View {
    @EnvironmentObject private var manager: CleanupManager
    let items: [CleanupItem]
    @State private var sortOrder = [KeyPathComparator(\CleanupItem.size, order: .reverse)]

    private var sortedItems: [CleanupItem] {
        items.sorted(using: sortOrder)
    }

    var body: some View {
        Table(sortedItems, selection: $manager.selectedIDs, sortOrder: $sortOrder) {
            TableColumn("") { item in
                Toggle("", isOn: Binding(
                    get: { manager.selectedIDs.contains(item.id) },
                    set: { _ in manager.toggleSelection(for: item) }
                ))
                .labelsHidden()
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

            TableColumn("Status") { item in
                if item.existsOnDisk {
                    Text(item.reason)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
                Button {
                    manager.reveal(item)
                } label: {
                    Image(systemName: "finder")
                }
                .help("Reveal in Finder")
            }
            .width(44)
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

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
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
