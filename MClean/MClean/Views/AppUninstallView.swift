import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppUninstallView: View {
    @EnvironmentObject private var manager: CleanupManager
    @Binding var isPresented: Bool
    @State private var inspected: AppUninstallInspector.InspectedApp?
    @State private var selectedIDs = Set<CleanupItem.ID>()
    @State private var isInspecting = false
    @State private var statusMessage: String?

    private var selectedItems: [CleanupItem] {
        inspected?.items.filter { selectedIDs.contains($0.id) } ?? []
    }

    private var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(spacing: 0) {
            MCleanModalHeader(
                title: "Uninstall App",
                subtitle: subtitle
            ) {
                isPresented = false
            }
            .padding(20)

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            WrappingHStack(spacing: 10, lineSpacing: 8) {
                Button {
                    chooseApp()
                } label: {
                    Label("Choose App…", systemImage: "app.dashed")
                }
                .buttonStyle(.mcleanAction)

                if inspected != nil {
                    Text("\(selectedItems.count) selected, \(ByteCount.string(selectedBytes))")
                        .foregroundStyle(.secondary)

                    Button {
                        manager.moveToStage(selectedItems)
                        finishAction(message: "Moved selected app data to Stage.")
                    } label: {
                        Label("Move Selected to Stage", systemImage: "tray.and.arrow.down")
                    }
                    .disabled(selectedItems.isEmpty)
                    .buttonStyle(.mcleanAccentAction)

                    if manager.showDirectTrashActions {
                        Button {
                            manager.moveToTrash(selectedItems)
                            finishAction(message: "Moved selected app data to Trash.")
                        } label: {
                            Label("Move Selected to Trash", systemImage: "trash")
                        }
                        .disabled(selectedItems.isEmpty)
                        .buttonStyle(.mcleanDestructiveAction)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    @ViewBuilder
    private var content: some View {
        if isInspecting {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Inspecting app data")
                    .foregroundStyle(.secondary)
            }
        } else if let inspected {
            List(inspected.items) { item in
                HStack(spacing: 10) {
                    Toggle("", isOn: Binding(
                        get: { selectedIDs.contains(item.id) },
                        set: { isOn in
                            if isOn {
                                selectedIDs.insert(item.id)
                            } else {
                                selectedIDs.remove(item.id)
                            }
                        }
                    ))
                    .labelsHidden()
                    .frame(width: 24)

                    Image(systemName: item.isDirectory ? "folder" : "doc")
                        .foregroundStyle(item.isDirectory ? .blue : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.reason)
                        Text(item.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    if item.risk == .high {
                        RiskBadge(risk: item.risk)
                    }

                    Text(ByteCount.string(item.size))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    Button {
                        manager.reveal(item)
                    } label: {
                        Image(systemName: "finder")
                    }
                    .buttonStyle(.borderless)
                    .help("Reveal in Finder")
                }
                .padding(.vertical, 3)
            }
        } else {
            VStack(spacing: 14) {
                ContentUnavailableView(
                    "Choose an App to Uninstall",
                    systemImage: "app.dashed",
                    description: Text(statusMessage ?? "Pick an app or drop one here. theMClean lists the app bundle and all related data so you can stage or trash it together.")
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first(where: { $0.pathExtension == "app" }) else { return false }
                inspect(appAt: url)
                return true
            }
        }
    }

    private var subtitle: String {
        guard let inspected else {
            return "Review everything an app leaves on this Mac before removing it"
        }
        return "\(inspected.name) (\(inspected.bundleID)) - \(inspected.items.count) item\(inspected.items.count == 1 ? "" : "s"), \(ByteCount.string(inspected.totalBytes))"
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Inspect"
        if panel.runModal() == .OK, let url = panel.url {
            inspect(appAt: url)
        }
    }

    private func inspect(appAt url: URL) {
        isInspecting = true
        statusMessage = nil
        selectedIDs.removeAll()
        Task.detached(priority: .userInitiated) {
            let result = AppUninstallInspector.inspect(appAt: url)
            await MainActor.run {
                isInspecting = false
                if let result {
                    inspected = result
                    // Preselect everything except the app bundle itself.
                    selectedIDs = Set(result.items.filter { $0.risk != .high }.map(\.id))
                } else {
                    inspected = nil
                    statusMessage = "Could not read that app bundle. Choose a .app from Applications."
                }
            }
        }
    }

    private func finishAction(message: String) {
        statusMessage = message
        guard let appURL = inspected?.appURL else { return }
        if FileManager.default.fileExists(atPath: appURL.path) {
            inspect(appAt: appURL)
        } else {
            inspected = nil
            selectedIDs.removeAll()
        }
    }
}
