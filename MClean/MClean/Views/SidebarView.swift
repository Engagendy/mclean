import SwiftUI

enum SidebarDestination: Hashable {
    case dashboard
    case allFindings
    case category(CleanupCategory)
}

struct SidebarView: View {
    @EnvironmentObject private var manager: CleanupManager
    @Binding var selectedDestination: SidebarDestination

    var body: some View {
        List(selection: $selectedDestination) {
            Section("Mode") {
                Picker("Scan mode", selection: Binding(
                    get: { manager.scanMode },
                    set: { manager.applyScanMode($0) }
                )) {
                    ForEach(ScanMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(manager.scanMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
}
