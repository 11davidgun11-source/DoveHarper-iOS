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
                ZStack {
                    Color.black.opacity(0.85)
                        .ignoresSafeArea()

                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            ProgressView()
                                .tint(.white)
                            Text("System Check")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                        .padding(.bottom, 12)

                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(Array(logLines.enumerated()), id: \.offset) { idx, line in
                                        Text(line)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(colorForLine(line))
                                            .id(idx)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .onChange(of: logLines.count) { _ in
                                withAnimation { proxy.scrollTo(logLines.count - 1, anchor: .bottom) }
                            }
                        }
                        .frame(maxHeight: 300)
                    }
                    .padding(20)
                    .frame(width: 380)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
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
                        Text("  \(err)").font(.caption2)
                    }

                    statusLine(icon: report.shopify.connected ? "checkmark.circle.fill" : "xmark.circle.fill",
                               label: "Shopify",
                               detail: report.shopify.detail,
                               color: report.shopify.connected ? .green : .red)
                    if let err = report.shopify.error {
                        Text("  \(err)").font(.caption2)
                    }

                    statusLine(icon: report.tryPost.connected ? "checkmark.circle.fill" : "xmark.circle.fill",
                               label: "TryPost",
                               detail: report.tryPost.detail,
                               color: report.tryPost.connected ? .green : .red)
                    if let err = report.tryPost.error {
                        Text("  \(err)").font(.caption2)
                    }
                }
            }
        }
        .task {
            await runConnectionCheck()
        }
    }

    private func runConnectionCheck() async {
        guard let settings = allSettings.first else { return }
        logLines = []
        isChecking = true

        addLog("Starting system check...")
        addLog("Timeout: 30s per service")

        let checker = ConnectionChecker { line in
            Task { @MainActor in
                self.addLog(line)
            }
        }

        let report = await checker.checkAll(settings: settings)
        connectionReport = report
        isChecking = false
        showConnectionReport = true
    }

    private func addLog(_ line: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logLines.append("[\(ts)] \(line)")
    }

    private func colorForLine(_ line: String) -> Color {
        if line.contains("OK") || line.contains("connected") || line.contains("found") {
            return .green
        } else if line.contains("FAIL") || line.contains("error") || line.contains("timeout") || line.contains("skip") {
            return .red
        } else if line.contains("...") || line.contains("checking") || line.contains("Connecting") {
            return .yellow
        }
        return .white
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
