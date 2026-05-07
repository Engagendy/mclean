import SwiftUI

enum SidebarDestination: Hashable {
    case dashboard
    case allFindings
    case category(CleanupCategory)
}

struct SidebarView: View {
    @EnvironmentObject private var manager: CleanupManager
    @Binding var selectedDestination: SidebarDestination
    private let modeColumns = [
        GridItem(.flexible(minimum: 72), spacing: 6),
        GridItem(.flexible(minimum: 72), spacing: 6)
    ]

    var body: some View {
        List(selection: $selectedDestination) {
            Section("Mode") {
                LazyVGrid(columns: modeColumns, alignment: .leading, spacing: 6) {
                    ForEach(ScanMode.allCases) { mode in
                        scanModeButton(mode)
                    }
                }
                .padding(.vertical, 2)

                Text(manager.scanMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(manager.scanMode.includedSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Views") {
                Label("Dashboard", systemImage: "chart.pie")
                    .tag(SidebarDestination.dashboard)
                Label("All Findings", systemImage: "sparkle.magnifyingglass")
                    .tag(SidebarDestination.allFindings)
            }

            Section("Categories") {
                ForEach(CleanupCategory.allCases) { category in
                    Label(category.rawValue, systemImage: category.symbolName)
                        .tag(SidebarDestination.category(category))
                }
            }

            Section("Scan") {
                Toggle("Caches", isOn: optionBinding(\.includeCaches))
                Toggle("Downloads", isOn: optionBinding(\.includeDownloads))
                Toggle("Temporary", isOn: optionBinding(\.includeTemporary))
                Toggle("Large files", isOn: optionBinding(\.includeLargeFiles))
                Toggle("Duplicates", isOn: optionBinding(\.includeDuplicates))
                Toggle("Old files", isOn: optionBinding(\.includeOldFiles))
                Toggle("Developer data", isOn: optionBinding(\.includeDeveloperData))
                Toggle("App leftovers", isOn: optionBinding(\.includeAppLeftovers))
                Toggle("Browser caches", isOn: optionBinding(\.includeBrowserCaches))
                Toggle("App support", isOn: optionBinding(\.includeAppSupport))
                Toggle("System storage", isOn: optionBinding(\.includeSystemStorage))

                VStack(alignment: .leading) {
                    Text("Large threshold")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Stepper("\(manager.options.largeFileThresholdMB) MB", value: intOptionBinding(\.largeFileThresholdMB), in: 100...5_000, step: 100)
                }

                VStack(alignment: .leading) {
                    Text("Old file age")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Stepper("\(manager.options.oldFileAgeDays) days", value: intOptionBinding(\.oldFileAgeDays), in: 90...2_000, step: 30)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func optionBinding(_ keyPath: WritableKeyPath<ScanOptions, Bool>) -> Binding<Bool> {
        Binding(
            get: { manager.options[keyPath: keyPath] },
            set: { value in
                manager.updateOptions { $0[keyPath: keyPath] = value }
                manager.markCustomScanMode()
            }
        )
    }

    private func intOptionBinding(_ keyPath: WritableKeyPath<ScanOptions, Int>) -> Binding<Int> {
        Binding(
            get: { manager.options[keyPath: keyPath] },
            set: { value in
                manager.updateOptions { $0[keyPath: keyPath] = value }
                manager.markCustomScanMode()
            }
        )
    }

    private func scanModeButton(_ mode: ScanMode) -> some View {
        let isSelected = manager.scanMode == mode

        return Button {
            manager.applyScanMode(mode)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: mode.sidebarSymbolName)
                    .font(.caption)
                    .frame(width: 14)
                Text(mode.sidebarTitle)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .padding(.horizontal, 8)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.12), lineWidth: 1)
        }
        .accessibilityLabel(mode.rawValue)
        .help(mode.rawValue)
    }
}

private extension ScanMode {
    var sidebarTitle: String {
        switch self {
        case .downloadsReview:
            return "Downloads"
        default:
            return rawValue
        }
    }

    var sidebarSymbolName: String {
        switch self {
        case .quick:
            return "bolt"
        case .deep:
            return "square.stack.3d.up"
        case .developer:
            return "hammer"
        case .downloadsReview:
            return "tray.and.arrow.down"
        case .custom:
            return "slider.horizontal.3"
        }
    }
}
