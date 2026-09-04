import SwiftUI
import SwiftData

@main
struct DoveHarperApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [BookEntity.self, QueueEntry.self, AppSettings.self])
    }
}

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            BookListView()
                .tabItem {
                    Label("Books", systemImage: "book.fill")
                }
                .tag(0)

            QueueView()
                .tabItem {
                    Label("Queue", systemImage: "clock.fill")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(2)
        }
        .tint(.red)
    }
}
