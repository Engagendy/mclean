import AppKit
import SwiftUI

struct ToolbarView: View {
    @EnvironmentObject private var manager: CleanupManager
    let visibleItems: [CleanupItem]
    @Binding var showingDeleteAlert: Bool
    @Binding var showingHelp: Bool
    @State private var showingTrashHistory = false
    @State private var showingStage = false
    @State private var showingDuplicateReview = false
    @State private var showingAppLeftovers = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cleanup Review")
                        .font(.title2.weight(.semibold))
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

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
                .buttonStyle(.mcleanAccentAction)
            }

            WrappingHStack(spacing: 8, lineSpacing: 8) {
                Button {
                    manager.selectRecommended()
                } label: {
                    Label("Recommended", systemImage: "checklist.checked")
                }
                .disabled(manager.items.isEmpty || isScanning)
                .buttonStyle(.mcleanAction)

                Button {
                    manager.select(visibleItems)
                } label: {
                    Label("Select Visible", systemImage: "checkmark.square")
                }
                .disabled(visibleItems.isEmpty || isScanning)
                .buttonStyle(.mcleanAction)

                Button {
                    manager.clearSelection()
                } label: {
                    Label("Clear", systemImage: "xmark.square")
                }
                .disabled(manager.selectedIDs.isEmpty || isScanning)
                .buttonStyle(.mcleanAction)

                Button {
                    manager.removeMissingItems()
                } label: {
                    Label("Remove Missing", systemImage: "minus.circle")
                }
                .disabled(manager.missingItemCount == 0 || isScanning)
                .buttonStyle(.mcleanAction)

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.mcleanAction)

                Button {
                    showingHelp = true
                } label: {
                    Label("Help", systemImage: "questionmark.circle")
                }
                .buttonStyle(.mcleanAction)

                Button {
                    showingDuplicateReview = true
                } label: {
                    Label("Duplicates", systemImage: "doc.on.doc")
                }
                .disabled(manager.duplicateGroups.isEmpty || isScanning)
                .buttonStyle(.mcleanAction)

                Button {
                    showingAppLeftovers = true
                } label: {
                    Label("Leftovers", systemImage: "app.badge")
                }
                .disabled(manager.appLeftoverGroups.isEmpty || isScanning)
                .buttonStyle(.mcleanAction)

                Button {
                    showingTrashHistory = true
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .disabled(manager.trashHistory.isEmpty)
                .buttonStyle(.mcleanAction)

                Button {
                    showingStage = true
                } label: {
                    Label(stageButtonTitle, systemImage: manager.staleStageEntries.isEmpty ? "tray.full" : "exclamationmark.triangle")
                }
                .disabled(manager.stageEntries.isEmpty)
                .buttonStyle(manager.staleStageEntries.isEmpty ? .mcleanAction : .mcleanWarningAction)

                Button {
                    manager.moveSelectedToStage()
                } label: {
                    Label("Move to Stage", systemImage: "tray.and.arrow.down")
                }
                .disabled(!manager.selectedItems.contains(where: \.canMoveToTrash) || isScanning)
                .buttonStyle(.mcleanAccentAction)

                if manager.showDirectTrashActions {
                    Button {
                        showingDeleteAlert = true
                    } label: {
                        Label("Move to Trash", systemImage: "trash")
                    }
                    .disabled(!manager.selectedItems.contains(where: \.canMoveToTrash) || isScanning)
                    .buttonStyle(.mcleanDestructiveAction)
                }
            }
            .controlSize(.small)
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
        .sheet(isPresented: $showingDuplicateReview) {
            DuplicateReviewView(isPresented: $showingDuplicateReview, showingDeleteAlert: $showingDeleteAlert)
                .environmentObject(manager)
        }
        .sheet(isPresented: $showingAppLeftovers) {
            AppLeftoverReviewView(isPresented: $showingAppLeftovers, showingDeleteAlert: $showingDeleteAlert)
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
        case .scanning:
            return "\(manager.scanProgress.phaseText) - \(manager.items.count) findings, \(manager.summary.scannedFiles) files scanned"
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

    private var stageButtonTitle: String {
        manager.staleStageEntries.isEmpty ? "Stage" : "Stage (\(manager.staleStageEntries.count))"
    }
}

struct AppLeftoverReviewView: View {
    @EnvironmentObject private var manager: CleanupManager
    @Binding var isPresented: Bool
    @Binding var showingDeleteAlert: Bool

    var body: some View {
        VStack(spacing: 0) {
            MCleanModalHeader(
                title: "App Leftovers",
                subtitle: "\(manager.appLeftoverGroups.count) app group\(manager.appLeftoverGroups.count == 1 ? "" : "s") found"
            ) {
                isPresented = false
            }
            .padding(18)

            Divider()

            if manager.appLeftoverGroups.isEmpty {
                ContentUnavailableView("No App Leftovers", systemImage: "app.badge", description: Text("Run a scan with App Leftovers enabled to review grouped leftovers."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(manager.appLeftoverGroups) { group in
                    AppLeftoverGroupRow(group: group)
                        .environmentObject(manager)
                }
                .listStyle(.inset)
            }

            Divider()

            WrappingHStack(spacing: 10, lineSpacing: 8) {
                Text("\(manager.selectedItems.filter { $0.category == .appLeftovers && $0.canMoveToTrash }.count) selected")
                    .foregroundStyle(.secondary)
                if manager.showDirectTrashActions {
                    Button {
                        isPresented = false
                        showingDeleteAlert = true
                    } label: {
                        Label("Review Selected in Trash", systemImage: "trash")
                    }
                    .disabled(!manager.selectedItems.contains { $0.category == .appLeftovers && $0.canMoveToTrash })
                    .buttonStyle(.mcleanDestructiveAction)
                }
                Button {
                    manager.moveSelectedToStage()
                    isPresented = false
                } label: {
                    Label("Move Selected to Stage", systemImage: "tray.and.arrow.down")
                }
                .disabled(!manager.selectedItems.contains { $0.category == .appLeftovers && $0.canMoveToTrash })
                .buttonStyle(.mcleanAccentAction)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
        .frame(minWidth: 760, minHeight: 560)
    }
}

private struct AppLeftoverGroupRow: View {
    @EnvironmentObject private var manager: CleanupManager
    let group: AppLeftoverGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "app.badge")
                    .foregroundStyle(.pink)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.bundleID)
                        .font(.headline)
                    Text("\(group.itemCount) item\(group.itemCount == 1 ? "" : "s"), \(ByteCount.string(group.totalBytes))")
                        .foregroundStyle(.secondary)
                    Text(group.highestConfidence.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(group.highestConfidence == .weakNameMatch ? .orange : .secondary)
                }
                Spacer()
                Button {
                    manager.selectAppLeftoverGroup(group)
                } label: {
                    Label("Select Group", systemImage: "checkmark.circle")
                }
                .buttonStyle(.mcleanAction)
            }

            ForEach(group.items.prefix(5)) { item in
                HStack(spacing: 8) {
                    Image(systemName: item.isDirectory ? "folder" : "doc")
                        .foregroundStyle(item.isDirectory ? .blue : .secondary)
                    Text(item.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(ByteCount.string(item.size))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct DuplicateReviewView: View {
    @EnvironmentObject private var manager: CleanupManager
    @Binding var isPresented: Bool
    @Binding var showingDeleteAlert: Bool

    private var selectedDuplicateCount: Int {
        manager.items.filter {
            $0.duplicateGroupID != nil && manager.selectedIDs.contains($0.id) && $0.canMoveToTrash
        }.count
    }

    private var selectedDuplicateBytes: Int64 {
        manager.items
            .filter { $0.duplicateGroupID != nil && manager.selectedIDs.contains($0.id) && $0.canMoveToTrash }
            .reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(spacing: 0) {
            MCleanModalHeader(
                title: "Duplicate Review",
                subtitle: "\(manager.duplicateGroups.count) groups, \(ByteCount.string(totalReclaimableBytes)) potential cleanup"
            ) {
                isPresented = false
            }
            .padding(20)

            Divider()

            if manager.duplicateGroups.isEmpty {
                ContentUnavailableView("No Duplicates", systemImage: "doc.on.doc", description: Text("Run a scan with Duplicates enabled to review identical files."))
            } else {
                List(manager.duplicateGroups) { group in
                    DuplicateGroupSection(group: group)
                }
            }

            Divider()

            WrappingHStack(spacing: 10, lineSpacing: 8) {
                Text("\(selectedDuplicateCount) selected, \(ByteCount.string(selectedDuplicateBytes))")
                    .foregroundStyle(.secondary)

                Button {
                    manager.moveSelectedToStage()
                    isPresented = false
                } label: {
                    Label("Move Selected to Stage", systemImage: "tray.and.arrow.down")
                }
                .disabled(selectedDuplicateCount == 0)
                .buttonStyle(.mcleanAccentAction)

                if manager.showDirectTrashActions {
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                        isPresented = false
                    } label: {
                        Label("Review Trash", systemImage: "trash")
                    }
                    .disabled(selectedDuplicateCount == 0)
                    .buttonStyle(.mcleanDestructiveAction)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .frame(minWidth: 920, minHeight: 620)
    }

    private var totalReclaimableBytes: Int64 {
        manager.duplicateGroups.reduce(0) { $0 + $1.reclaimableBytes }
    }
}

private struct DuplicateGroupSection: View {
    @EnvironmentObject private var manager: CleanupManager
    let group: DuplicateReviewGroup

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                WrappingHStack(spacing: 10, lineSpacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.name)
                            .font(.headline)
                            .lineLimit(1)
                        Text("\(group.duplicateCount) identical files, \(ByteCount.string(group.representativeSize)) each, \(ByteCount.string(group.reclaimableBytes)) reclaimable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Menu {
                        ForEach(DuplicateKeepStrategy.allCases) { strategy in
                            Button {
                                manager.selectDuplicates(in: group, keeping: strategy)
                            } label: {
                                Label("Keep \(strategy.rawValue)", systemImage: strategy.symbolName)
                            }
                        }
                        Divider()
                        Button {
                            manager.clearDuplicateSelection(in: group)
                        } label: {
                            Label("Clear Group Selection", systemImage: "xmark.circle")
                        }
                    } label: {
                        Label("Select Duplicates", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.mcleanAction)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(group.items) { item in
                    DuplicateItemRow(item: item)
                }
            }
            .padding(.vertical, 6)
        }
    }
}

private struct DuplicateItemRow: View {
    @EnvironmentObject private var manager: CleanupManager
    let item: CleanupItem

    private var isSelected: Binding<Bool> {
        Binding(
            get: { manager.selectedIDs.contains(item.id) },
            set: { _ in manager.toggleSelection(for: item) }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: isSelected)
                .labelsHidden()
                .disabled(!item.canMoveToTrash)
                .frame(width: 24)

            Image(systemName: item.isDirectory ? "folder" : "doc")
                .foregroundStyle(item.isDirectory ? .blue : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(ByteCount.string(item.size)) - \(item.modifiedAt.map(DuplicateReviewView.dateFormatter.string(from:)) ?? "Unknown date")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                manager.showDetails(for: item)
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .help("Show Details")

            Button {
                manager.reveal(item)
            } label: {
                Image(systemName: "finder")
            }
            .buttonStyle(.borderless)
            .disabled(!item.existsOnDisk)
            .help("Reveal in Finder")

            Button {
                NSWorkspace.shared.open(item.url)
            } label: {
                Image(systemName: "eye")
            }
            .buttonStyle(.borderless)
            .disabled(!item.existsOnDisk)
            .help("Preview")
        }
    }
}

private extension DuplicateReviewView {
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

struct StageView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var manager: CleanupManager
    @State private var pendingPermanentDelete: StageEntry?
    @State private var confirmingMoveStaleToTrash = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                MCleanModalTitle(title: "Stage", subtitle: stageSubtitle)

                Spacer(minLength: 16)

                if !manager.staleStageEntries.isEmpty {
                    Button {
                        confirmingMoveStaleToTrash = true
                    } label: {
                        Label("Trash Stale", systemImage: "trash")
                    }
                    .buttonStyle(.mcleanDestructiveAction)
                }
                Button {
                    manager.revealStageFolder()
                } label: {
                    Label("Reveal Stage", systemImage: "folder")
                }
                .buttonStyle(.mcleanAction)

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.mcleanAction)
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
        .confirmationDialog("Move stale staged items to Trash?", isPresented: $confirmingMoveStaleToTrash) {
            Button("Move \(manager.staleStageEntries.count) Item\(manager.staleStageEntries.count == 1 ? "" : "s") to Trash", role: .destructive) {
                manager.moveStaleStageEntriesToTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only staged items at least \(manager.stageReminderAgeDays) days old are included.")
        }
    }

    private var stageSubtitle: String {
        if manager.staleStageEntries.isEmpty {
            return "Items moved out of their original locations for review"
        }
        return "\(manager.staleStageEntries.count) item\(manager.staleStageEntries.count == 1 ? "" : "s") staged for \(manager.stageReminderAgeDays)+ days"
    }
}

private struct StageRow: View {
    @EnvironmentObject private var manager: CleanupManager
    let entry: StageEntry
    @Binding var pendingPermanentDelete: StageEntry?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
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
                if entry.isStale(reminderAgeDays: manager.stageReminderAgeDays) {
                    Label("\(entry.ageDays()) days in Stage", systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            stageActions
                .controlSize(.small)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                manager.revealStagedItem(entry)
            } label: {
                Label("Reveal Staged Item", systemImage: "tray.full")
            }
            .disabled(!entry.existsInStage)

            Button {
                manager.revealOriginalLocation(for: entry)
            } label: {
                Label("Reveal Original Location", systemImage: "folder")
            }

            Button {
                copyPath(entry.originalURL.path)
            } label: {
                Label("Copy Original Path", systemImage: "doc.on.doc")
            }

            Button {
                copyPath(entry.stagedURL.path)
            } label: {
                Label("Copy Staged Path", systemImage: "doc.on.doc.fill")
            }
        }
    }

    private func copyPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    @ViewBuilder
    private var stageActions: some View {
        if entry.existsInStage {
            WrappingHStack(spacing: 6, lineSpacing: 6) {
                Button {
                    manager.restoreFromStage(entry)
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                .disabled(!entry.canRestore)
                .buttonStyle(.mcleanAction)

                Button {
                    manager.moveStagedToTrash(entry)
                } label: {
                    Label("Trash", systemImage: "trash")
                }
                .buttonStyle(.mcleanDestructiveAction)

                Button(role: .destructive) {
                    pendingPermanentDelete = entry
                } label: {
                    Label("Delete", systemImage: "trash.slash")
                }
                .buttonStyle(.mcleanDestructiveAction)
            }
            .frame(maxWidth: 260, alignment: .trailing)
        } else {
            Button {
                manager.removeMissingStageEntry(entry)
            } label: {
                Label("Remove", systemImage: "minus.circle")
            }
            .buttonStyle(.mcleanAction)
        }
    }
}

struct TrashHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var manager: CleanupManager

    var body: some View {
        VStack(spacing: 0) {
            MCleanModalHeader(
                title: "Trash History",
                subtitle: "Items MClean moved to Trash in recent cleanup actions"
            ) {
                dismiss()
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
                    .buttonStyle(.mcleanAction)
                }
                .padding(.vertical, 4)
            }

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

struct MCleanModalHeader: View {
    let title: String
    let subtitle: String
    let closeAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            MCleanModalTitle(title: title, subtitle: subtitle)

            Spacer(minLength: 16)

            Button("Close") {
                closeAction()
            }
            .keyboardShortcut(.cancelAction)
            .buttonStyle(.mcleanAction)
        }
    }
}

struct MCleanModalTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct WrappingHStack: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var measuredWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + spacing + size.width > maxWidth {
                measuredWidth = max(measuredWidth, x)
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }

            if x > 0 {
                x += spacing
            }
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }

        measuredWidth = max(measuredWidth, x)
        return CGSize(width: min(measuredWidth, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + spacing + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }

            if x > bounds.minX {
                x += spacing
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(size)
            )
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct MCleanActionButtonStyle: ButtonStyle {
    enum Tone {
        case neutral
        case accent
        case destructive
        case warning
    }

    @Environment(\.isEnabled) private var isEnabled
    let tone: Tone

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .lineLimit(1)
            .minimumScaleFactor(0.88)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(foregroundColor)
            .frame(minHeight: 30)
            .padding(.horizontal, 10)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(backgroundColor.opacity(configuration.isPressed ? pressedOpacity : normalOpacity))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.48)
    }

    private var foregroundColor: Color {
        switch tone {
        case .neutral:
            return .primary
        case .accent:
            return .accentColor
        case .destructive:
            return .red
        case .warning:
            return .orange
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .neutral:
            return .secondary
        case .accent:
            return .accentColor
        case .destructive:
            return .red
        case .warning:
            return .orange
        }
    }

    private var borderColor: Color {
        switch tone {
        case .neutral:
            return Color.secondary.opacity(0.12)
        case .accent:
            return Color.accentColor.opacity(0.35)
        case .destructive:
            return Color.red.opacity(0.35)
        case .warning:
            return Color.orange.opacity(0.35)
        }
    }

    private var normalOpacity: Double {
        tone == .neutral ? 0.08 : 0.14
    }

    private var pressedOpacity: Double {
        tone == .neutral ? 0.14 : 0.22
    }
}

extension ButtonStyle where Self == MCleanActionButtonStyle {
    static var mcleanAction: MCleanActionButtonStyle {
        MCleanActionButtonStyle(tone: .neutral)
    }

    static var mcleanAccentAction: MCleanActionButtonStyle {
        MCleanActionButtonStyle(tone: .accent)
    }

    static var mcleanDestructiveAction: MCleanActionButtonStyle {
        MCleanActionButtonStyle(tone: .destructive)
    }

    static var mcleanWarningAction: MCleanActionButtonStyle {
        MCleanActionButtonStyle(tone: .warning)
    }
}
