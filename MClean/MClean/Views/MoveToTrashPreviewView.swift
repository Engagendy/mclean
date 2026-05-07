import SwiftUI

struct MoveToTrashPreviewView: View {
    @EnvironmentObject private var manager: CleanupManager
    @Binding var isPresented: Bool

    private struct CategorySection: Identifiable {
        let category: CleanupCategory
        let items: [CleanupItem]

        var id: CleanupCategory { category }
    }

    private var selectedItems: [CleanupItem] {
        manager.selectedItems
    }

    private var groupedItems: [CategorySection] {
        CleanupCategory.allCases.compactMap { category in
            let matches = selectedItems.filter { $0.category == category }
            return matches.isEmpty ? nil : CategorySection(category: category, items: matches)
        }
    }

    private var highRiskCount: Int {
        selectedItems.filter { $0.risk == .high }.count
    }

    private var missingCount: Int {
        selectedItems.filter { !$0.existsOnDisk }.count
    }

    private var protectedCount: Int {
        selectedItems.filter { !$0.canMoveToTrash }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            MCleanModalHeader(
                title: "Review Before Moving to Trash",
                subtitle: "\(selectedItems.count) selected, \(ByteCount.string(manager.selectedBytes)) total"
            ) {
                isPresented = false
            }
            .padding(20)

            Divider()

            if highRiskCount > 0 || missingCount > 0 || protectedCount > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    if highRiskCount > 0 {
                        Label("\(highRiskCount) high-risk item\(highRiskCount == 1 ? "" : "s") selected. Review these in Finder before removing.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    if missingCount > 0 {
                        Label("\(missingCount) item\(missingCount == 1 ? "" : "s") no longer exist on disk and will be ignored.", systemImage: "questionmark.folder")
                            .foregroundStyle(.secondary)
                    }
                    if protectedCount > 0 {
                        Label("\(protectedCount) protected item\(protectedCount == 1 ? "" : "s") will be ignored.", systemImage: "lock.shield")
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.orange.opacity(highRiskCount > 0 ? 0.10 : 0.0))

                Divider()
            }

            List {
                ForEach(groupedItems, id: \.id) { section in
                    Section(section.category.rawValue) {
                        ForEach(section.items, id: \.id) { item in
                            MoveToTrashPreviewRow(item: item)
                        }
                    }
                }
            }

            Divider()

            WrappingHStack(spacing: 10, lineSpacing: 8) {
                Button {
                    if let firstHighRisk = selectedItems.first(where: { $0.risk == .high }) {
                        manager.reveal(firstHighRisk)
                    }
                } label: {
                    Label("Review High Risk", systemImage: "finder")
                }
                .disabled(highRiskCount == 0)
                .buttonStyle(.mcleanWarningAction)

                Button(role: .destructive) {
                    manager.moveSelectedToTrash()
                    isPresented = false
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedItems.allSatisfy { !$0.canMoveToTrash })
                .buttonStyle(.mcleanDestructiveAction)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .frame(minWidth: 760, minHeight: 520)
    }
}

private struct MoveToTrashPreviewRow: View {
    let item: CleanupItem

    private var iconName: String {
        item.isDirectory ? "folder" : "doc"
    }

    private var iconColor: Color {
        item.isDirectory ? .blue : .secondary
    }

    private var pathColor: Color {
        item.existsOnDisk ? .secondary : .red
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .lineLimit(1)
                Text(item.path)
                    .font(.caption)
                    .foregroundStyle(pathColor)
                    .lineLimit(1)
            }

            Spacer()

            RiskBadge(risk: item.risk)
            ProtectionBadge(protection: item.protection)
            Text(ByteCount.string(item.size))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
