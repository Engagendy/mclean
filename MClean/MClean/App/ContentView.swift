import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var manager: CleanupManager
    @State private var selectedCategory: CleanupCategory?
    @State private var showingDeleteAlert = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    private var filteredItems: [CleanupItem] {
        guard let selectedCategory else { return manager.items }
        return manager.items.filter { $0.category == selectedCategory }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedCategory: $selectedCategory)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            VStack(spacing: 0) {
                ToolbarView(visibleItems: filteredItems, showingDeleteAlert: $showingDeleteAlert)
                Divider()
                FullDiskAccessBanner()
                Divider()
                ResultsTable(items: filteredItems)
                StatusBar()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(isPresented: $showingDeleteAlert) {
                MoveToTrashPreviewView(isPresented: $showingDeleteAlert)
                    .environmentObject(manager)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 980, minHeight: 640)
        .onAppear {
            manager.refreshFullDiskAccessStatus()
        }
    }
}
