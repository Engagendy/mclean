import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var manager: CleanupManager
    @Binding var selectedCategory: CleanupCategory?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MClean")
                    .font(.title2.weight(.semibold))
                Text("Mac cleanup scanner")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            List(selection: Binding(
                get: { selectedCategory?.rawValue ?? "all" },
                set: { value in
                    selectedCategory = CleanupCategory.allCases.first { $0.rawValue == value }
                }
            )) {
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

                Section {
                    Label("All Findings", systemImage: "sparkle.magnifyingglass")
                        .tag("all")
                }

                Section("Categories") {
                    ForEach(CleanupCategory.allCases) { category in
                        Label(category.rawValue, systemImage: category.symbolName)
                            .tag(category.rawValue)
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
                        Stepper("\(manager.options.largeFileThresholdMB) MB", value: $manager.options.largeFileThresholdMB, in: 100...5_000, step: 100)
                    }

                    VStack(alignment: .leading) {
                        Text("Old file age")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Stepper("\(manager.options.oldFileAgeDays) days", value: $manager.options.oldFileAgeDays, in: 90...2_000, step: 30)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(.ultraThinMaterial)
    }

    private func optionBinding(_ keyPath: WritableKeyPath<ScanOptions, Bool>) -> Binding<Bool> {
        Binding(
            get: { manager.options[keyPath: keyPath] },
            set: { value in
                manager.options[keyPath: keyPath] = value
                manager.markCustomScanMode()
            }
        )
    }
}
