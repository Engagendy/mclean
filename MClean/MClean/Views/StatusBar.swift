import SwiftUI

struct StatusBar: View {
    @EnvironmentObject private var manager: CleanupManager

    var body: some View {
        HStack {
            if case .scanning = manager.state {
                ProgressView()
                    .controlSize(.small)
                Text("\(manager.scanProgress.phaseText) - \(manager.summary.scannedFiles) files scanned")
                Text(manager.scanProgress.estimateText)
                if !manager.scanProgress.skippedPhases.isEmpty {
                    Text("\(manager.scanProgress.skippedPhases.count) phase\(manager.scanProgress.skippedPhases.count == 1 ? "" : "s") skipped")
                }
                Button {
                    manager.skipCurrentScanPhase()
                } label: {
                    Label("Skip Category", systemImage: "forward.end")
                }
                .disabled(manager.scanProgress.phase == nil)
                .help("Skip the current scan category and continue with the next one")
            } else if let message = manager.lastDeletionMessage {
                Text(message)
            } else if case .cancelled = manager.state {
                Text("Scan cancelled")
            } else {
                Text("\(manager.summary.scannedFiles) files scanned")
            }

            Spacer()

            if manager.summary.skippedItems > 0 {
                Text("\(manager.summary.skippedItems) skipped")
            }
            if manager.summary.protectedLocationsBlocked > 0 {
                Text("\(manager.summary.protectedLocationsBlocked) protected")
            }
            if manager.missingItemCount > 0 {
                Text("\(manager.missingItemCount) missing")
            }
            Text("\(manager.selectedItems.filter(\.canMoveToTrash).count) selected")
            Text(ByteCount.string(manager.selectedBytes))
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
