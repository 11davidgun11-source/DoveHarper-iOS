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
    @State private var logLines: [String] = []

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                BookListView()
                    .tabItem { Label("Books", systemImage: "book.fill") }.tag(0)
                QueueView()
                    .tabItem { Label("Queue", systemImage: "clock.fill") }.tag(1)
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }.tag(2)
            }
            .tint(.red)

            if isChecking {
                ZStack {
                    Color.black.opacity(0.85).ignoresSafeArea()
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            ProgressView().tint(.white)
                            Text("System Check").font(.headline).foregroundStyle(.white)
                        }.padding(.bottom, 12)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(Array(logLines.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(colorForLine(line))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .frame(maxHeight: 260)
                    }
                    .padding(16)
                    .frame(width: 370)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .transition(.opacity)
            }
        }
        .alert("Dove Harper — System Check", isPresented: $showConnectionReport) {
            Button("OK") { showConnectionReport = false }
        } message: {
            if let report = connectionReport {
                VStack(alignment: .leading, spacing: 4) {
                    resultLine("GitHub", report.github)
                    resultLine("Shopify", report.shopify)
                    resultLine("TryPost", report.tryPost)
                }
            }
        }
        .task { await runChecks() }
    }

    private func runChecks() async {
        guard let settings = allSettings.first else { return }
        logLines = []
        isChecking = true

        add("Starting system check...")
        add("Each service has a 30s timeout.")

        // --- GitHub ---
        add("")
        add("► GitHub")
        if settings.githubPAT.isEmpty {
            add("  FAIL — no PAT configured")
        } else {
            add("  PAT: \(settings.githubPAT.prefix(10))...")
            add("  GET /repos/\(settings.githubOwner)/\(settings.githubRepo)/contents/...")
            let result = await withTimeout(seconds: 30) {
                await checkGitHub(settings: settings)
            }
            if let r = result {
                add("  \(r.detail)")
                if let e = r.error { add("  \(e)") }
                var report = connectionReport ?? ConnectionReport()
                report.github = r
                connectionReport = report
            } else {
                add("  FAIL — timed out after 30s")
                var report = connectionReport ?? ConnectionReport()
                report.github = ServiceStatus(connected: false, detail: "Timeout", error: "GitHub timed out after 30s.")
                connectionReport = report
            }
        }

        // --- Shopify ---
        add("")
        add("► Shopify")
        if settings.shopifyAccessToken.isEmpty {
            add("  FAIL — no access token")
        } else {
            add("  Token: \(settings.shopifyAccessToken.prefix(10))...")
            add("  GET https://\(settings.shopifyShopURL)/admin/api/2026-07/shop.json")
            let result = await withTimeout(seconds: 30) {
                await checkShopify(settings: settings)
            }
            if let r = result {
                add("  \(r.detail)")
                if let e = r.error { add("  \(e)") }
                var report = connectionReport ?? ConnectionReport()
                report.shopify = r
                connectionReport = report
            } else {
                add("  FAIL — timed out after 30s")
                var report = connectionReport ?? ConnectionReport()
                report.shopify = ServiceStatus(connected: false, detail: "Timeout", error: "Shopify timed out after 30s.")
                connectionReport = report
            }
        }

        // --- TryPost ---
        add("")
        add("► TryPost")
        if settings.tryPostAPIKey.isEmpty {
            add("  FAIL — no API key")
        } else {
            add("  Key: \(settings.tryPostAPIKey.prefix(20))...")
            add("  GET http://100.101.187.102:8000/api/social-accounts")
            let result = await withTimeout(seconds: 30) {
                await checkTryPost(settings: settings)
            }
            if let r = result {
                add("  \(r.detail)")
                if let e = r.error { add("  \(e)") }
                var report = connectionReport ?? ConnectionReport()
                report.tryPost = r
                connectionReport = report
            } else {
                add("  FAIL — timed out after 30s")
                var report = connectionReport ?? ConnectionReport()
                report.tryPost = ServiceStatus(connected: false, detail: "Timeout", error: "TryPost timed out after 30s.")
                connectionReport = report
            }
        }

        add("")
        add("Done.")

        // Brief pause so user can read the log
        try? await Task.sleep(nanoseconds: 800_000_000)
        isChecking = false
        showConnectionReport = true
    }

    // MARK: - Individual checks

    private func checkGitHub(settings: AppSettings) async -> ServiceStatus {
        let path = "/repos/\(settings.githubOwner)/\(settings.githubRepo)/contents/dove-harper-site/content/books"
        let url = URL(string: "https://api.github.com\(path)")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(settings.githubPAT)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        do {
            add("  Connecting to api.github.com...")
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            add("  HTTP \(code)")
            if code == 200 {
                if let items = try? JSONDecoder().decode([GitHubContent].self, from: data) {
                    let books = items.filter { $0.name.hasSuffix(".json") && !$0.name.hasPrefix("_") }
                    let names = books.map { $0.name.replacingOccurrences(of: ".json", with: "") }
                    return ServiceStatus(connected: true, detail: "OK — \(books.count) book\(books.count == 1 ? "" : "s"): \(names.joined(separator: ", "))", error: nil)
                }
                return ServiceStatus(connected: true, detail: "OK — connected", error: nil)
            } else if code == 401 {
                return ServiceStatus(connected: false, detail: "HTTP 401", error: "Invalid PAT.")
            } else if code == 404 {
                return ServiceStatus(connected: false, detail: "HTTP 404", error: "Repo not found.")
            } else {
                return ServiceStatus(connected: false, detail: "HTTP \(code)", error: "API error.")
            }
        } catch {
            return ServiceStatus(connected: false, detail: "Error", error: error.localizedDescription)
        }
    }

    private func checkShopify(settings: AppSettings) async -> ServiceStatus {
        let url = URL(string: "https://\(settings.shopifyShopURL)/admin/api/2026-07/shop.json")!
        var req = URLRequest(url: url)
        req.setValue(settings.shopifyAccessToken, forHTTPHeaderField: "X-Shopify-Access-Token")

        do {
            add("  Connecting to \(settings.shopifyShopURL)...")
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            add("  HTTP \(code)")
            if code == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let shop = json["shop"] as? [String: Any],
                   let name = shop["name"] as? String {
                    return ServiceStatus(connected: true, detail: "OK — \(name)", error: nil)
                }
                return ServiceStatus(connected: true, detail: "OK — connected", error: nil)
            } else {
                return ServiceStatus(connected: false, detail: "HTTP \(code)", error: "Bad token or shop URL.")
            }
        } catch {
            return ServiceStatus(connected: false, detail: "Error", error: error.localizedDescription)
        }
    }

    private func checkTryPost(settings: AppSettings) async -> ServiceStatus {
        let url = URL(string: "http://100.101.187.102:8000/api/social-accounts")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(settings.tryPostAPIKey)", forHTTPHeaderField: "Authorization")

        do {
            add("  Connecting to 100.101.187.102:8000...")
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            add("  HTTP \(code)")
            if code == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let accounts = json["accounts"] as? [[String: Any]] {
                    let names = accounts.compactMap { $0["platform"] as? String }
                    return ServiceStatus(connected: true, detail: "OK — \(names.count) account\(names.count == 1 ? "" : "s"): \(names.joined(separator: ", "))", error: nil)
                }
                return ServiceStatus(connected: true, detail: "OK — connected", error: nil)
            } else {
                return ServiceStatus(connected: false, detail: "HTTP \(code)", error: "Bad API key.")
            }
        } catch {
            return ServiceStatus(connected: false, detail: "Offline", error: "Server at 100.101.187.102:8000 not reachable.")
        }
    }

    // MARK: - Helpers

    private func add(_ line: String) {
        logLines.append(line)
    }

    private func colorForLine(_ line: String) -> Color {
        if line.contains("OK") || line.contains("found") { return .green }
        if line.contains("FAIL") || line.contains("Error") || line.contains("error") || line.contains("timed out") || line.contains("Offline") { return .red }
        if line.contains("...") || line.contains("Connecting") || line.hasPrefix("►") { return .yellow }
        return .white
    }

    private func resultLine(_ label: String, _ status: ServiceStatus) -> some View {
        HStack(spacing: 6) {
            Image(systemName: status.connected ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(status.connected ? .green : .red)
                .font(.caption)
            Text("\(label): \(status.detail)")
                .font(.caption)
        }
    }
}

// MARK: - Timeout helper

func withTimeout<T>(seconds: Double, operation: @escaping @Sendable () async -> T) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}
