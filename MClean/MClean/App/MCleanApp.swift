import SwiftUI

@main
struct MCleanApp: App {
    @StateObject private var manager = CleanupManager()

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
