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
    @Environment(\.modelContext) private var modelContext
    @Query private var allSettings: [AppSettings]
    @State private var selectedTab = 0
    @State private var showConnectionReport = false
    @State private var connectionReport: ConnectionReport?
    @State private var isChecking = true

    var body: some View {
        ZStack {
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

            if isChecking {
                ProgressView("Checking connections...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .alert("Dove Harper — System Check", isPresented: $showConnectionReport) {
            Button("OK") { showConnectionReport = false }
        } message: {
            if let report = connectionReport {
                VStack(alignment: .leading, spacing: 4) {
                    statusLine(icon: report.github.connected ? "checkmark.circle.fill" : "xmark.circle.fill",
                               label: "GitHub",
                               detail: report.github.detail,
                               color: report.github.connected ? .green : .red)
                    if let err = report.github.error {
                        Text("  → \(err)").font(.caption2)
                    }

                    statusLine(icon: report.shopify.connected ? "checkmark.circle.fill" : "xmark.circle.fill",
                               label: "Shopify",
                               detail: report.shopify.detail,
                               color: report.shopify.connected ? .green : .red)
                    if let err = report.shopify.error {
                        Text("  → \(err)").font(.caption2)
                    }

                    statusLine(icon: report.tryPost.connected ? "checkmark.circle.fill" : "xmark.circle.fill",
                               label: "TryPost",
                               detail: report.tryPost.detail,
                               color: report.tryPost.connected ? .green : .red)
                    if let err = report.tryPost.error {
                        Text("  → \(err)").font(.caption2)
                    }
                }
            }
        }
        .task {
            guard let settings = allSettings.first else { return }
            let checker = ConnectionChecker()
            let report = await checker.checkAll(settings: settings)
            connectionReport = report
            isChecking = false
            showConnectionReport = true
        }
    }

    private func statusLine(icon: String, label: String, detail: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.caption)
            Text("\(label): \(detail)")
                .font(.caption)
        }
    }
}
