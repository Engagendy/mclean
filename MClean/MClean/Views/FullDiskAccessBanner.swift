import SwiftUI

struct FullDiskAccessBanner: View {
    @EnvironmentObject private var manager: CleanupManager

    var body: some View {
        if !manager.fullDiskAccessStatus.isLikelyGranted {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Full Disk Access improves scan coverage")
                        .font(.headline)
                    Text("Open Full Disk Access, add MClean, turn it on, then quit and reopen the app. This lets MClean inspect protected locations like Mail, Messages, Safari, iPhone backups, and large app containers.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button {
                    manager.openFullDiskAccessSettings()
                } label: {
                    Label("Open Settings", systemImage: "gear")
                }

                Button {
                    manager.refreshFullDiskAccessStatus()
                } label: {
                    Label("Recheck", systemImage: "arrow.clockwise")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.orange.opacity(0.10))
        }
    }
}
