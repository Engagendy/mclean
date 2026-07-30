import AppKit
import Combine

/// Menu bar presence built on NSStatusItem instead of SwiftUI's MenuBarExtra.
/// MenuBarExtra alongside a WindowGroup livelocks the SwiftUI scene graph on
/// some macOS versions (the menu bar host requests updates in a loop), so the
/// menu is plain AppKit and its dynamic content is built only when opened.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let manager: CleanupManager
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    init(manager: CleanupManager) {
        self.manager = manager
        super.init()
        manager.$showMenuBarExtra
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in
                self?.setVisible(visible)
            }
            .store(in: &cancellables)
    }

    private func setVisible(_ visible: Bool) {
        if visible {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "internaldrive", accessibilityDescription: "theMClean")
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.delegate = self
            item.menu = menu
            statusItem = item
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            rebuild(menu)
        }
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        let space = manager.diskSpace
        if space.totalBytes > 0 {
            menu.addItem(infoItem("\(ByteCount.string(space.freeBytes)) free of \(ByteCount.string(space.totalBytes))"))
        }
        if let lastScan = manager.lastScanDescription {
            menu.addItem(infoItem("Last scan \(lastScan)"))
        }
        if !manager.items.isEmpty {
            menu.addItem(infoItem("\(manager.items.count) findings, \(ByteCount.string(manager.summary.reclaimableBytes)) potential cleanup"))
        }
        let staleCount = manager.staleStageEntries.count
        if staleCount > 0 {
            menu.addItem(infoItem("\(staleCount) staged item\(staleCount == 1 ? "" : "s") awaiting review"))
        }
        if menu.items.isEmpty == false {
            menu.addItem(.separator())
        }

        let scanItem = NSMenuItem(
            title: manager.isScanning ? "Scanning…" : "Scan Now",
            action: #selector(scanNow),
            keyEquivalent: ""
        )
        scanItem.target = self
        scanItem.isEnabled = !manager.isScanning
        menu.addItem(scanItem)

        let openItem = NSMenuItem(title: "Open theMClean", action: #selector(openApp), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit theMClean", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func scanNow() {
        manager.scan()
    }

    @objc private func openApp() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // No open windows: relaunching through Launch Services triggers the
            // reopen path, which makes SwiftUI create the main window again.
            NSWorkspace.shared.open(Bundle.main.bundleURL)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
