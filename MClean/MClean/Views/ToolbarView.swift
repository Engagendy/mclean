import SwiftUI

struct ToolbarView: View {
    @EnvironmentObject private var manager: CleanupManager
    let visibleItems: [CleanupItem]
    @Binding var showingDeleteAlert: Bool

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
                showingDeleteAlert = true
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(manager.selectedItems.isEmpty || isScanning)
        }
        .padding(18)
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
