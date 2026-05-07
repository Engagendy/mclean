import SwiftUI

struct ToolbarView: View {
    @EnvironmentObject private var manager: CleanupManager
    let visibleItems: [CleanupItem]
    @Binding var showingDeleteAlert: Bool
    @State private var showingTrashHistory = false
    @State private var showingStage = false

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cleanup Review")
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                if manager.isScanning {
                    manager.cancelScan()
                } else {
                    manager.scan()
                }
            } label: {
                if isScanning {
                    Label("Cancel", systemImage: "xmark.circle")
                } else {
                    Label("Scan", systemImage: "arrow.clockwise")
                }
            }
            .keyboardShortcut("r", modifiers: [.command])

            Button {
                manager.selectRecommended()
            } label: {
                Label("Recommended", systemImage: "checklist.checked")
            }
            .disabled(manager.items.isEmpty || isScanning)

            Button {
                manager.select(visibleItems)
            } label: {
                Label("Select Visible", systemImage: "checkmark.square")
            }
            .disabled(visibleItems.isEmpty || isScanning)

            Button {
                manager.clearSelection()
            } label: {
                Label("Clear", systemImage: "xmark.square")
            }
            .disabled(manager.selectedIDs.isEmpty || isScanning)

            Button {
                manager.removeMissingItems()
            } label: {
                Label("Remove Missing", systemImage: "minus.circle")
            }
            .disabled(manager.missingItemCount == 0 || isScanning)

            Button {
                showingTrashHistory = true
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .disabled(manager.trashHistory.isEmpty)

            Button {
                showingStage = true
            } label: {
                Label("Stage", systemImage: "tray.full")
            }
            .disabled(manager.stageEntries.isEmpty)

            Button {
                manager.moveSelectedToStage()
            } label: {
                Label("Move to Stage", systemImage: "tray.and.arrow.down")
            }
            .disabled(!manager.selectedItems.contains(where: \.canMoveToTrash) || isScanning)

            Button {
                showingDeleteAlert = true
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(!manager.selectedItems.contains(where: \.canMoveToTrash) || isScanning)
        }
        .padding(18)
        .sheet(isPresented: $showingTrashHistory) {
            TrashHistoryView()
                .environmentObject(manager)
        }
        .sheet(isPresented: $showingStage) {
            StageView()
                .environmentObject(manager)
        }
    }

    private var isScanning: Bool {
        if case .scanning = manager.state { return true }
        return false
    }

    private var subtitle: String {
        switch manager.state {
        case .idle:
            return "Choose scan options, then click Scan"
        case .scanning(let message):
            return "\(message) - \(manager.items.count) findings, \(manager.summary.scannedFiles) files scanned"
        case .finished:
            let scanText = manager.lastScanDescription.map { "Last scan \($0)" } ?? "Scan complete"
            let missing = manager.missingItemCount > 0 ? ", \(manager.missingItemCount) missing" : ""
            return "\(manager.items.count) findings\(missing), \(ByteCount.string(manager.summary.reclaimableBytes)) potential cleanup - \(scanText)"
        case .cancelled:
            return "Scan cancelled - \(manager.items.count) partial findings kept"
        case .failed(let message):
            return message
        }
    }
}

struct StageView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var manager: CleanupManager
    @State private var pendingPermanentDelete: StageEntry?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stage")
                        .font(.title2.weight(.semibold))
                    Text("Items moved out of their original locations for review")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    manager.revealStageFolder()
                } label: {
                    Label("Reveal Stage", systemImage: "folder")
                }
            }
            .padding(20)

            Divider()

            if manager.stageEntries.isEmpty {
                ContentUnavailableView(
                    "Stage is Empty",
                    systemImage: "tray",
                    description: Text("Move selected findings to Stage when you want to test before deleting.")
                )
            } else {
                List(manager.stageEntries) { entry in
                    StageRow(entry: entry, pendingPermanentDelete: $pendingPermanentDelete)
                }
            }

            Divider()

            HStack {
                Text("\(manager.stageEntries.count) staged item\(manager.stageEntries.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(20)
        }
        .frame(minWidth: 820, minHeight: 560)
        .alert("Delete Permanently?", isPresented: Binding(
            get: { pendingPermanentDelete != nil },
            set: { if !$0 { pendingPermanentDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                pendingPermanentDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let pendingPermanentDelete {
                    manager.deleteStagedPermanently(pendingPermanentDelete)
                }
                pendingPermanentDelete = nil
            }
        } message: {
            Text("This removes the staged item immediately instead of sending it to Trash.")
        }
    }
}

private struct StageRow: View {
    @EnvironmentObject private var manager: CleanupManager
    let entry: StageEntry
    @Binding var pendingPermanentDelete: StageEntry?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.existsInStage ? entry.category.symbolName : "questionmark.folder")
                .foregroundStyle(entry.existsInStage ? .blue : .secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.itemName)
                    .lineLimit(1)
                Text(entry.originalURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(ByteCount.string(entry.size)) - \(entry.category.rawValue) - \(StageView.dateFormatter.string(from: entry.stagedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if entry.existsInStage {
                Button {
                    manager.restoreFromStage(entry)
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                .disabled(!entry.canRestore)

                Button {
                    manager.moveStagedToTrash(entry)
                } label: {
                    Label("Trash", systemImage: "trash")
                }

                Button(role: .destructive) {
                    pendingPermanentDelete = entry
                } label: {
                    Label("Delete", systemImage: "trash.slash")
                }
            } else {
                Button {
                    manager.removeMissingStageEntry(entry)
                } label: {
                    Label("Remove", systemImage: "minus.circle")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct TrashHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var manager: CleanupManager

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trash History")
                        .font(.title2.weight(.semibold))
                    Text("Items MClean moved to Trash in recent cleanup actions")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)

            Divider()

            List(manager.trashHistory) { entry in
                HStack(spacing: 12) {
                    Image(systemName: entry.canRestore ? "arrow.uturn.backward.circle" : "trash")
                        .foregroundStyle(entry.canRestore ? .blue : .secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.itemName)
                            .lineLimit(1)
                        Text(entry.originalURL.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text("\(ByteCount.string(entry.size)) - \(Self.dateFormatter.string(from: entry.movedAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        manager.restoreFromTrash(entry)
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!entry.canRestore)
                }
                .padding(.vertical, 4)
            }

            Divider()

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(20)
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private extension StageView {
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
