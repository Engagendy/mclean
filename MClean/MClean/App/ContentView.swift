import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var manager: CleanupManager
    @State private var selectedDestination = SidebarDestination.dashboard
    @State private var showingDeleteAlert = false
    @State private var showingHelp = false
    @State private var isSidebarVisible = true
    @State private var findingsFilter = FindingsFilter()

    private var filteredItems: [CleanupItem] {
        let baseItems: [CleanupItem]
        switch selectedDestination {
        case .dashboard, .allFindings:
            baseItems = manager.items
        case .category(let category):
            baseItems = manager.items.filter { $0.category == category }
        }
        return baseItems.filter { findingsFilter.matches($0) }
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
                DashboardDetailView(showingDeleteAlert: $showingDeleteAlert, showingHelp: $showingHelp)
            case .allFindings, .category:
                FindingsDetailView(
                    visibleItems: filteredItems,
                    totalItems: manager.items.count,
                    filter: $findingsFilter,
                    showingDeleteAlert: $showingDeleteAlert,
                    showingHelp: $showingHelp
                )
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
        .sheet(isPresented: $showingHelp) {
            HelpView()
        }
    }
}

struct FindingsFilter: Equatable {
    var searchText = ""
    var pathText = ""
    var minimumSizeMB = 0
    var risk: CleanupRisk?
    var protection: CleanupProtection?
    var category: CleanupCategory?
    var sourceKind: CleanupSourceKind?
    var modifiedDate = ModifiedDateFilter.any

    var isActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !pathText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            minimumSizeMB > 0 ||
            risk != nil ||
            protection != nil ||
            category != nil ||
            sourceKind != nil ||
            modifiedDate != .any
    }

    func matches(_ item: CleanupItem) -> Bool {
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        if !normalizedSearch.isEmpty {
            let searchable = "\(item.name) \(item.path) \(item.reason)".localizedLowercase
            guard searchable.contains(normalizedSearch) else { return false }
        }

        let normalizedPath = pathText.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        if !normalizedPath.isEmpty {
            guard item.path.localizedLowercase.contains(normalizedPath) else { return false }
        }

        if minimumSizeMB > 0 {
            guard item.size >= Int64(minimumSizeMB) * 1_024 * 1_024 else { return false }
        }

        if let risk, item.risk != risk { return false }
        if let protection, item.protection != protection { return false }
        if let category, item.category != category { return false }
        if let sourceKind, item.resolvedSourceKind != sourceKind { return false }
        if !modifiedDate.matches(item.modifiedAt) { return false }
        return true
    }
}

enum ModifiedDateFilter: String, CaseIterable, Identifiable {
    case any = "Any"
    case last30Days = "Last 30 Days"
    case last90Days = "Last 90 Days"
    case lastYear = "Last Year"
    case olderThanYear = "Older Than 1 Year"

    var id: String { rawValue }

    func matches(_ date: Date?) -> Bool {
        guard self != .any else { return true }
        guard let date else { return false }
        let calendar = Calendar.current
        let now = Date()
        switch self {
        case .any:
            return true
        case .last30Days:
            return date >= (calendar.date(byAdding: .day, value: -30, to: now) ?? .distantPast)
        case .last90Days:
            return date >= (calendar.date(byAdding: .day, value: -90, to: now) ?? .distantPast)
        case .lastYear:
            return date >= (calendar.date(byAdding: .year, value: -1, to: now) ?? .distantPast)
        case .olderThanYear:
            return date < (calendar.date(byAdding: .year, value: -1, to: now) ?? .distantPast)
        }
    }
}

struct FindingsDetailView: View {
    let visibleItems: [CleanupItem]
    let totalItems: Int
    @Binding var filter: FindingsFilter
    @Binding var showingDeleteAlert: Bool
    @Binding var showingHelp: Bool

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView(visibleItems: visibleItems, showingDeleteAlert: $showingDeleteAlert, showingHelp: $showingHelp)
            Divider()
            FullDiskAccessBanner()
            Divider()
            FindingsFilterBar(filter: $filter, visibleItems: visibleItems, totalCount: totalItems)
            Divider()
            ResultsTable(items: visibleItems)
            StatusBar()
        }
    }
}

struct FindingsFilterBar: View {
    @EnvironmentObject private var manager: CleanupManager
    @Binding var filter: FindingsFilter
    let visibleItems: [CleanupItem]
    let totalCount: Int

    private var visibleBytes: Int64 {
        visibleItems.filter(\.canMoveToTrash).reduce(0) { $0 + $1.size }
    }

    private var selectedVisibleBytes: Int64 {
        visibleItems
            .filter { manager.selectedIDs.contains($0.id) && $0.canMoveToTrash }
            .reduce(0) { $0 + $1.size }
    }

    private var selectedVisibleCount: Int {
        visibleItems.filter { manager.selectedIDs.contains($0.id) && $0.canMoveToTrash }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WrappingHStack(spacing: 10, lineSpacing: 8) {
                Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.headline)

                TextField("Search name, path, or reason", text: $filter.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)

                TextField("Path contains", text: $filter.pathText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)

                Stepper("Min \(filter.minimumSizeMB) MB", value: $filter.minimumSizeMB, in: 0...10_000, step: 100)
                    .frame(width: 150)

                Text("\(visibleItems.count) of \(totalCount)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            WrappingHStack(spacing: 10, lineSpacing: 8) {
                Picker("Risk", selection: $filter.risk) {
                    Text("Any Risk").tag(Optional<CleanupRisk>.none)
                    ForEach(CleanupRisk.allCases, id: \.self) { risk in
                        Text(risk.rawValue).tag(Optional(risk))
                    }
                }
                .frame(width: 150)

                Picker("Protection", selection: $filter.protection) {
                    Text("Any Protection").tag(Optional<CleanupProtection>.none)
                    ForEach(CleanupProtection.allCases, id: \.self) { protection in
                        Text(protection.rawValue).tag(Optional(protection))
                    }
                }
                .frame(width: 190)

                Picker("Category", selection: $filter.category) {
                    Text("Any Category").tag(Optional<CleanupCategory>.none)
                    ForEach(CleanupCategory.allCases) { category in
                        Text(category.rawValue).tag(Optional(category))
                    }
                }
                .frame(width: 190)

                Picker("Source", selection: $filter.sourceKind) {
                    Text("Any Source").tag(Optional<CleanupSourceKind>.none)
                    ForEach(CleanupSourceKind.allCases) { sourceKind in
                        Text(sourceKind.rawValue).tag(Optional(sourceKind))
                    }
                }
                .frame(width: 170)

                Picker("Modified", selection: $filter.modifiedDate) {
                    ForEach(ModifiedDateFilter.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .frame(width: 190)

                Text("\(ByteCount.string(visibleBytes)) visible")
                    .foregroundStyle(.secondary)

                Text("\(selectedVisibleCount) selected, \(ByteCount.string(selectedVisibleBytes))")
                    .foregroundStyle(.secondary)

                Button {
                    filter = FindingsFilter()
                } label: {
                    Label("Clear Filters", systemImage: "xmark.circle")
                }
                .disabled(!filter.isActive)
                .buttonStyle(.mcleanAction)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .controlSize(.small)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

struct DashboardDetailView: View {
    @EnvironmentObject private var manager: CleanupManager
    @Binding var showingDeleteAlert: Bool
    @Binding var showingHelp: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dashboard")
                        .font(.title2.weight(.semibold))
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 16)

                HStack(spacing: 8) {
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
                    .buttonStyle(.mcleanAccentAction)

                    Menu {
                        Button {
                            showingHelp = true
                        } label: {
                            Label("Help", systemImage: "questionmark.circle")
                        }

                        Divider()

                        SettingsLink {
                            Label("Settings", systemImage: "gearshape")
                        }

                        Divider()

                        Button {
                            manager.selectRecommended()
                            if manager.showDirectTrashActions {
                                showingDeleteAlert = true
                            } else {
                                manager.moveSelectedToStage()
                            }
                        } label: {
                            Label(manager.showDirectTrashActions ? "Clean Recommended" : "Stage Recommended", systemImage: "checklist.checked")
                        }
                        .disabled(manager.items.isEmpty || manager.isScanning)

                        Button {
                            manager.refreshDiskSpace()
                        } label: {
                            Label("Refresh Disk Status", systemImage: "arrow.clockwise.circle")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .buttonStyle(.mcleanAction)
                    .help("More Actions")
                }
                .controlSize(.small)
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
        if case .scanning = manager.state {
            return "\(manager.scanProgress.phaseText) - \(manager.items.count) findings streamed"
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
