import AppKit
import SwiftUI

@main
struct MCleanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var manager = CleanupManager()

    init() {
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
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        MCleanWindowState.clearSavedLayout()

        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
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
