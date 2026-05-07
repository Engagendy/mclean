import AppKit
import SwiftUI
import UserNotifications

@main
struct MCleanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var manager = CleanupManager()

    init() {
        if MCleanCLI.shouldRun {
            MCleanCLI.runAndExit()
        }
        MCleanWindowState.clearSavedLayout()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(manager)
                .frame(minWidth: 980, minHeight: 640)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Scan") {
                    manager.scan()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(manager)
                .frame(minWidth: 620, minHeight: 520)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var manager: CleanupManager
    @State private var manualExclusionPath = ""
    @State private var profileName = ""

    var body: some View {
        TabView {
            scanSettings
                .tabItem {
                    Label("Scan", systemImage: "slider.horizontal.3")
                }

            exclusionsSettings
                .tabItem {
                    Label("Exclusions", systemImage: "folder.badge.minus")
                }

            stageSettings
                .tabItem {
                    Label("Stage", systemImage: "tray.full")
                }

            scheduleSettings
                .tabItem {
                    Label("Schedule", systemImage: "calendar.badge.clock")
                }
        }
        .padding(20)
    }

    private var scanSettings: some View {
        Form {
            Section("Profile") {
                Picker("Scan mode", selection: Binding(
                    get: { manager.scanMode },
                    set: { manager.applyScanMode($0) }
                )) {
                    ForEach(ScanMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                Text(manager.scanMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(manager.scanMode.includedSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Saved Profiles") {
                HStack(spacing: 8) {
                    TextField("Profile name", text: $profileName)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        manager.saveCurrentScanProfile(named: profileName)
                        profileName = ""
                    } label: {
                        Label("Save Current", systemImage: "plus")
                    }
                    .disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if manager.savedScanProfiles.isEmpty {
                    Text("No custom profiles saved.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(manager.savedScanProfiles) { profile in
                        HStack(spacing: 10) {
                            Label(profile.name, systemImage: "slider.horizontal.3")
                            Spacer()
                            Button {
                                manager.applySavedScanProfile(profile)
                            } label: {
                                Label("Apply", systemImage: "checkmark.circle")
                            }
                            Button(role: .destructive) {
                                manager.deleteSavedScanProfile(profile)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section("Categories") {
                Toggle("Caches", isOn: boolOptionBinding(\.includeCaches))
                Toggle("Downloads", isOn: boolOptionBinding(\.includeDownloads))
                Toggle("Temporary", isOn: boolOptionBinding(\.includeTemporary))
                Toggle("Large files", isOn: boolOptionBinding(\.includeLargeFiles))
                Toggle("Duplicates", isOn: boolOptionBinding(\.includeDuplicates))
                Toggle("Old files", isOn: boolOptionBinding(\.includeOldFiles))
                Toggle("Developer data", isOn: boolOptionBinding(\.includeDeveloperData))
                Toggle("App leftovers", isOn: boolOptionBinding(\.includeAppLeftovers))
                Toggle("Browser caches", isOn: boolOptionBinding(\.includeBrowserCaches))
                Toggle("App support", isOn: boolOptionBinding(\.includeAppSupport))
                Toggle("System storage", isOn: boolOptionBinding(\.includeSystemStorage))
            }

            Section("Limits") {
                Stepper("\(manager.options.largeFileThresholdMB) MB large-file threshold", value: intOptionBinding(\.largeFileThresholdMB), in: 100...5_000, step: 100)
                Stepper("\(manager.options.oldFileAgeDays) days old-file age", value: intOptionBinding(\.oldFileAgeDays), in: 90...2_000, step: 30)
                Stepper("\(manager.options.maxResults) maximum results", value: intOptionBinding(\.maxResults), in: 250...10_000, step: 250)
            }
        }
        .formStyle(.grouped)
    }

    private var exclusionsSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Scan Exclusions")
                    .font(.title3.weight(.semibold))
                Text("Excluded folders are skipped during scans and removed from current findings.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("Folder path", text: $manualExclusionPath)
                    .textFieldStyle(.roundedBorder)
                Button {
                    chooseExclusionFolder()
                } label: {
                    Label("Choose", systemImage: "folder")
                }
                Button {
                    manager.addExcludedPath(manualExclusionPath)
                    manager.markCustomScanMode()
                    manualExclusionPath = ""
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .disabled(manualExclusionPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Divider()

            if manager.options.excludedPaths.isEmpty {
                ContentUnavailableView("No Exclusions", systemImage: "folder.badge.minus", description: Text("Add folders that MClean should never scan."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(manager.options.excludedPaths, id: \.self) { path in
                    HStack(spacing: 10) {
                        Image(systemName: "folder")
                            .foregroundStyle(.blue)
                        Text(path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(role: .destructive) {
                            manager.removeExcludedPath(path)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove Exclusion")
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private var stageSettings: some View {
        Form {
            Section("Review Reminder") {
                Stepper(
                    "\(manager.stageReminderAgeDays) days before staged items are marked stale",
                    value: $manager.stageReminderAgeDays,
                    in: 1...90,
                    step: 1
                )
                Text("\(manager.staleStageEntries.count) staged item\(manager.staleStageEntries.count == 1 ? "" : "s") currently meet this reminder age.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Cleanup Actions") {
                Toggle("Show direct Move to Trash actions", isOn: $manager.showDirectTrashActions)
                Text("When off, primary cleanup controls route selected files through Stage first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var scheduleSettings: some View {
        Form {
            Section("Scheduled Scans") {
                Toggle("Run scheduled scans", isOn: $manager.scheduledScansEnabled)
                Stepper(
                    "Every \(manager.scheduledScanIntervalDays) day\(manager.scheduledScanIntervalDays == 1 ? "" : "s")",
                    value: $manager.scheduledScanIntervalDays,
                    in: 1...30,
                    step: 1
                )
                Text(manager.nextScheduledScanDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Scheduled scans only report findings. Cleanup stays manual.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    manager.runScheduledScanNow()
                } label: {
                    Label("Run Scheduled Scan Now", systemImage: "play.circle")
                }
                .disabled(manager.isScanning)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseExclusionFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Exclusion"
        if panel.runModal() == .OK, let url = panel.url {
            manager.addExcludedPath(url.path)
            manager.markCustomScanMode()
        }
    }

    private func boolOptionBinding(_ keyPath: WritableKeyPath<ScanOptions, Bool>) -> Binding<Bool> {
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

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        NSWindow.allowsAutomaticWindowTabbing = true
        MCleanWindowState.clearSavedLayout()

        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

enum MCleanWindowState {
    static func clearSavedLayout() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys {
            if key.hasPrefix("NSWindow Frame") || key.hasPrefix("NSSplitView Subview Frames") {
                defaults.removeObject(forKey: key)
            }
        }
        defaults.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        defaults.set(true, forKey: "ApplePersistenceIgnoreState")
        defaults.synchronize()
    }
}
