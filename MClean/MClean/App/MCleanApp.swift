import AppKit
import SwiftUI

@main
struct MCleanApp: App {
    @StateObject private var manager = CleanupManager()

    init() {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(manager)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Scan") {
                    manager.scan()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}
