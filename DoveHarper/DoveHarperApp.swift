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
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    var body: some View {
        TabView(selection: $selectedTab) {
            BookListView()
                .tabItem { Label("Books", systemImage: "book.fill") }.tag(0)
            QueueView()
                .tabItem { Label("Queue", systemImage: "clock.fill") }.tag(1)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }.tag(2)
        }
        .tint(.red)
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .task { await runChecks() }
    }

    private func ensureSettings() -> AppSettings {
        if let existing = allSettings.first {
            return existing
        }
        let s = AppSettings()
        modelContext.insert(s)
        try? modelContext.save()
        return s
    }

    private func runChecks() async {
        let settings = ensureSettings()
        var lines: [String] = []

        // --- GitHub ---
        lines.append("GitHub:")
        if settings.githubPAT.isEmpty {
            lines.append("  No PAT configured.")
        } else {
            let url = URL(string: "https://api.github.com/repos/\(settings.githubOwner)/\(settings.githubRepo)/contents/dove-harper-site/content/books")!
            var req = URLRequest(url: url)
            req.setValue("Bearer \(settings.githubPAT)", forHTTPHeaderField: "Authorization")
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if code == 200, let items = try? JSONDecoder().decode([GitHubContent].self, from: data) {
                    let books = items.filter { $0.name.hasSuffix(".json") && !$0.name.hasPrefix("_") }
                    let names = books.map { $0.name.replacingOccurrences(of: ".json", with: "") }
                    lines.append("  Connected. \(books.count) book\(books.count == 1 ? "" : "s"): \(names.joined(separator: ", "))")
                } else if code == 401 {
                    lines.append("  HTTP 401 — invalid PAT.")
                } else if code == 404 {
                    lines.append("  HTTP 404 — repo not found.")
                } else {
                    lines.append("  HTTP \(code) error.")
                }
            } catch {
                lines.append("  \(error.localizedDescription)")
            }
        }

        alertTitle = "System Check"
        alertMessage = lines.joined(separator: "\n")
        showAlert = true
    }
}
