import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var manager: CleanupManager
    @State private var selectedDestination = SidebarDestination.dashboard
    @State private var showingDeleteAlert = false
    @State private var isSidebarVisible = true

    private var filteredItems: [CleanupItem] {
        switch selectedDestination {
        case .dashboard, .allFindings:
            return manager.items
        case .category(let category):
            return manager.items.filter { $0.category == category }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                SidebarView(selectedDestination: $selectedDestination)
                    .frame(width: 260)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Divider()
            }

            detailContent
        }
        .frame(minWidth: 980, minHeight: 640)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        isSidebarVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
            }
        }
        .onAppear {
            manager.refreshFullDiskAccessStatus()
            manager.refreshDiskSpace()
        }
    }

    private var detailContent: some View {
        VStack(spacing: 0) {
            switch selectedDestination {
            case .dashboard:
                DashboardDetailView(showingDeleteAlert: $showingDeleteAlert)
            case .allFindings, .category:
                FindingsDetailView(visibleItems: filteredItems, showingDeleteAlert: $showingDeleteAlert)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingDeleteAlert) {
            MoveToTrashPreviewView(isPresented: $showingDeleteAlert)
                .environmentObject(manager)
        }
        .sheet(item: $manager.detailItem) { item in
            FileDetailsView(item: item)
                .environmentObject(manager)
        }
    }
}

struct FindingsDetailView: View {
    let visibleItems: [CleanupItem]
    @Binding var showingDeleteAlert: Bool

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView(visibleItems: visibleItems, showingDeleteAlert: $showingDeleteAlert)
            Divider()
            FullDiskAccessBanner()
            Divider()
            ResultsTable(items: visibleItems)
            StatusBar()
        }
    }
}

struct DashboardDetailView: View {
    @EnvironmentObject private var manager: CleanupManager
    @Binding var showingDeleteAlert: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dashboard")
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
                    if manager.isScanning {
                        Label("Cancel", systemImage: "xmark.circle")
                    } else {
                        Label("Scan", systemImage: "arrow.clockwise")
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Menu {
                    Button {
                        manager.selectRecommended()
                        showingDeleteAlert = true
                    } label: {
                        Label("Clean Recommended", systemImage: "checklist.checked")
                    }
                    .disabled(manager.items.isEmpty || manager.isScanning)

                    Button {
                        manager.refreshDiskSpace()
                    } label: {
                        Label("Refresh Disk Status", systemImage: "arrow.clockwise.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .help("More Actions")
            }
            .padding(18)

            Divider()
            FullDiskAccessBanner()
            Divider()

            ScrollView {
                CleanupDashboardView()
                    .padding(.horizontal, 22)
                    .padding(.vertical, 20)
            }
            .background {
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor),
                        Color(nsColor: .controlBackgroundColor).opacity(0.72)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            StatusBar()
        }
    }

    private var subtitle: String {
        if case .scanning(let message) = manager.state {
            return "\(message) - \(manager.items.count) findings streamed"
        }
        if let lastScan = manager.lastScanDescription {
            return "Last scan \(lastScan)"
        }
        return "Disk usage, cleanup potential, and scan category breakdown"
    }
}

struct CleanupDashboardView: View {
    @EnvironmentObject private var manager: CleanupManager

    private var potentialAfterCleanup: Int64 {
        max(manager.diskSpace.freeBytes + manager.summary.reclaimableBytes, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 22) {
                DiskHealthPanel(snapshot: manager.diskSpace, reclaimableBytes: manager.summary.reclaimableBytes)
                    .frame(width: 300)

                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        DashboardMetric(
                            title: "Free Space",
                            value: ByteCount.string(manager.diskSpace.freeBytes),
                            subtitle: "After cleanup: \(ByteCount.string(potentialAfterCleanup))",
                            systemImage: "internaldrive",
                            color: .blue
                        )

                        DashboardMetric(
                            title: "Cleanup Potential",
                            value: ByteCount.string(manager.summary.reclaimableBytes),
                            subtitle: "\(manager.items.count) findings, \(manager.protectedItemCount) protected",
                            systemImage: "sparkle.magnifyingglass",
                            color: .green
                        )
                    }

                    HStack(spacing: 12) {
                        DashboardMetric(
                            title: "Selected",
                            value: ByteCount.string(manager.selectedBytes),
                            subtitle: "\(manager.selectedItems.filter(\.canMoveToTrash).count) ready for Trash",
                            systemImage: "checkmark.circle",
                            color: .orange
                        )

                        DashboardMetric(
                            title: "Scanned",
                            value: "\(manager.summary.scannedFiles.formatted())",
                            subtitle: "\(manager.summary.skippedItems) skipped, \(manager.missingItemCount) missing",
                            systemImage: "list.bullet.rectangle",
                            color: .secondary
                        )
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                DiskUsageBar(snapshot: manager.diskSpace, reclaimableBytes: manager.summary.reclaimableBytes)
                CategoryBreakdownView(totals: Array(manager.categoryTotals.prefix(8)))
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var diskColor: Color {
        switch manager.diskSpace.usedFraction {
        case 0..<0.75: return .green
        case 0..<0.9: return .orange
        default: return .red
        }
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }
}

private struct DiskHealthPanel: View {
    let snapshot: DiskSpaceSnapshot
    let reclaimableBytes: Int64

    private var freeAfterCleanup: Int64 {
        snapshot.freeBytes + reclaimableBytes
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                DiskUsageRing(fraction: snapshot.usedFraction, reclaimableFraction: reclaimableFraction)
                    .frame(width: 190, height: 190)

                VStack(spacing: 4) {
                    Text(snapshot.usedFraction.formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("Used")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 4) {
                Text(ByteCount.string(snapshot.usedBytes))
                    .font(.headline.monospacedDigit())
                Text("of \(ByteCount.string(snapshot.totalBytes)) on this volume")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("\(ByteCount.string(freeAfterCleanup)) free after selected cleanup potential")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var reclaimableFraction: Double {
        guard snapshot.totalBytes > 0 else { return 0 }
        return min(Double(reclaimableBytes) / Double(snapshot.totalBytes), snapshot.usedFraction)
    }
}

private struct DiskUsageRing: View {
    let fraction: Double
    let reclaimableFraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.16), lineWidth: 18)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(
                        colors: [.blue, .cyan, .blue],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Circle()
                .trim(from: max(fraction - reclaimableFraction, 0), to: fraction)
                .stroke(.green, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.snappy(duration: 0.35), value: fraction)
        .animation(.snappy(duration: 0.35), value: reclaimableFraction)
    }
}

private struct DashboardMetric: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.background.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DiskUsageBar: View {
    let snapshot: DiskSpaceSnapshot
    let reclaimableBytes: Int64

    private var reclaimableFraction: Double {
        guard snapshot.totalBytes > 0 else { return 0 }
        return min(Double(reclaimableBytes) / Double(snapshot.totalBytes), snapshot.usedFraction)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Volume Usage")
                    .font(.headline)
                Spacer()
                Text("\(ByteCount.string(snapshot.freeBytes)) free")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.secondary.opacity(0.18))
                    Capsule()
                        .fill(.blue.opacity(0.72))
                        .frame(width: width * snapshot.usedFraction)
                    Capsule()
                        .fill(.green.opacity(0.9))
                        .frame(width: width * reclaimableFraction)
                        .offset(x: max(width * (snapshot.usedFraction - reclaimableFraction), 0))
                }
            }
            .frame(height: 12)

            HStack(spacing: 14) {
                LegendDot(label: "Used", color: .blue)
                LegendDot(label: "Cleanup potential", color: .green)
                LegendDot(label: "Free", color: .secondary.opacity(0.35))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CategoryBreakdownView: View {
    let totals: [(category: CleanupCategory, bytes: Int64)]

    private var maxBytes: Int64 {
        totals.map(\.bytes).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Findings by Category")
                .font(.headline)

            if totals.isEmpty {
                Text("Run a scan to see category totals.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(totals, id: \.category) { total in
                    HStack(spacing: 8) {
                        Label(total.category.rawValue, systemImage: total.category.symbolName)
                            .font(.subheadline)
                            .frame(width: 170, alignment: .leading)
                            .lineLimit(1)

                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(.secondary.opacity(0.12))
                                Capsule()
                                    .fill(categoryColor(total.category).opacity(0.78))
                                    .frame(width: max(proxy.size.width * CGFloat(Double(total.bytes) / Double(maxBytes)), 4))
                            }
                        }
                        .frame(height: 9)

                        Text(ByteCount.string(total.bytes))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 88, alignment: .trailing)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func categoryColor(_ category: CleanupCategory) -> Color {
        switch category {
        case .largeFiles: return .orange
        case .duplicates: return .purple
        case .caches: return .blue
        case .downloads: return .teal
        case .temporary: return .green
        case .oldFiles: return .red
        case .developerData: return .indigo
        case .appLeftovers: return .pink
        case .appSupport: return .brown
        case .systemStorage: return .gray
        }
    }
}

private struct LegendDot: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
        }
    }
}
