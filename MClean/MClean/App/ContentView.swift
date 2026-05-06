import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var manager: CleanupManager
    @State private var selectedCategory: CleanupCategory?
    @State private var showingDeleteAlert = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    private var filteredItems: [CleanupItem] {
        guard let selectedCategory else { return manager.items }
        return manager.items.filter { $0.category == selectedCategory }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedCategory: $selectedCategory)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            VStack(spacing: 0) {
                ToolbarView(visibleItems: filteredItems, showingDeleteAlert: $showingDeleteAlert)
                Divider()
                FullDiskAccessBanner()
                Divider()
                CleanupDashboardView()
                Divider()
                ResultsTable(items: filteredItems)
                StatusBar()
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
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 980, minHeight: 640)
        .onAppear {
            manager.refreshFullDiskAccessStatus()
            manager.refreshDiskSpace()
        }
    }
}

struct CleanupDashboardView: View {
    @EnvironmentObject private var manager: CleanupManager

    private var potentialAfterCleanup: Int64 {
        max(manager.diskSpace.freeBytes + manager.summary.reclaimableBytes, 0)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                DashboardMetric(
                    title: "Disk Used",
                    value: ByteCount.string(manager.diskSpace.usedBytes),
                    subtitle: "\(percent(manager.diskSpace.usedFraction)) of \(ByteCount.string(manager.diskSpace.totalBytes))",
                    systemImage: "internaldrive",
                    color: diskColor
                )

                DashboardMetric(
                    title: "Free Space",
                    value: ByteCount.string(manager.diskSpace.freeBytes),
                    subtitle: "After cleanup: \(ByteCount.string(potentialAfterCleanup))",
                    systemImage: "gauge.with.dots.needle.bottom.50percent",
                    color: .blue
                )

                DashboardMetric(
                    title: "Cleanup Potential",
                    value: ByteCount.string(manager.summary.reclaimableBytes),
                    subtitle: "\(manager.items.count) findings, \(manager.protectedItemCount) protected",
                    systemImage: "sparkle.magnifyingglass",
                    color: .green
                )

                DashboardMetric(
                    title: "Selected",
                    value: ByteCount.string(manager.selectedBytes),
                    subtitle: "\(manager.selectedItems.filter(\.canMoveToTrash).count) ready for Trash",
                    systemImage: "checkmark.circle",
                    color: .orange
                )
            }

            HStack(alignment: .center, spacing: 16) {
                DiskUsageBar(snapshot: manager.diskSpace, reclaimableBytes: manager.summary.reclaimableBytes)

                Divider()

                CategoryBreakdownView(totals: Array(manager.categoryTotals.prefix(6)))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial)
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
        .padding(10)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
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
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(ByteCount.string(snapshot.freeBytes)) free")
                    .font(.caption)
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
        VStack(alignment: .leading, spacing: 7) {
            Text("Findings by Category")
                .font(.caption.weight(.semibold))

            if totals.isEmpty {
                Text("Run a scan to see category totals.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(totals, id: \.category) { total in
                    HStack(spacing: 8) {
                        Label(total.category.rawValue, systemImage: total.category.symbolName)
                            .font(.caption)
                            .frame(width: 145, alignment: .leading)
                            .lineLimit(1)

                        GeometryReader { proxy in
                            Capsule()
                                .fill(categoryColor(total.category).opacity(0.75))
                                .frame(width: max(proxy.size.width * CGFloat(Double(total.bytes) / Double(maxBytes)), 4))
                        }
                        .frame(height: 7)

                        Text(ByteCount.string(total.bytes))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 78, alignment: .trailing)
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
