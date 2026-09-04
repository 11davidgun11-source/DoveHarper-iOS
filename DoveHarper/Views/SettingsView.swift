import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allSettings: [AppSettings]
    @State private var settings: AppSettings
    @State private var showingAutocorrectRules = false
    @State private var newRulePattern = ""
    @State private var newRuleReplacement = ""
    @State private var saved = false

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("GitHub") {
                    TextField("Personal Access Token", text: $settings.githubPAT)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    TextField("Owner", text: $settings.githubOwner)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    TextField("Repository", text: $settings.githubRepo)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }

                Section("Shopify") {
                    TextField("Shop URL (e.g. myshop.myshopify.com)", text: $settings.shopifyShopURL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    TextField("Access Token", text: $settings.shopifyAccessToken)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }

                Section("Defaults") {
                    TextField("Default Author", text: $settings.defaultAuthor)
                    TextField("Timezone", text: $settings.timezone)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }

                Section("Text Autocorrect") {
                    Button {
                        showingAutocorrectRules = true
                    } label: {
                        HStack {
                            Text("Manage Rules")
                            Spacer()
                            Text("\(settings.autocorrectRules.count) rules")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                        }
                    }
                }

                Section {
                    Button {
                        saveSettings()
                        saved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            saved = false
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if saved {
                                Label("Saved!", systemImage: "checkmark")
                                    .foregroundStyle(.green)
                            } else {
                                Text("Save Settings")
                            }
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear { loadSettings() }
            .sheet(isPresented: $showingAutocorrectRules) {
                NavigationStack {
                    List {
                        ForEach(Array(settings.autocorrectRules.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                            HStack {
                                Text(key)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.right")
                                Text(value)
                            }
                        }
                        .onDelete { indexSet in
                            let sorted = settings.autocorrectRules.sorted(by: { $0.key < $1.key })
                            for index in indexSet {
                                let key = sorted[index].key
                                settings.autocorrectRules.removeValue(forKey: key)
                            }
                        }

                        Section("Add Rule") {
                            TextField("Pattern (e.g. explicit content)", text: $newRulePattern)
                            TextField("Replacement (e.g. Explicit Content)", text: $newRuleReplacement)
                            Button("Add Rule") {
                                if !newRulePattern.isEmpty && !newRuleReplacement.isEmpty {
                                    settings.autocorrectRules[newRulePattern.lowercased()] = newRuleReplacement
                                    newRulePattern = ""
                                    newRuleReplacement = ""
                                }
                            }
                            .disabled(newRulePattern.isEmpty || newRuleReplacement.isEmpty)
                        }
                    }
                    .navigationTitle("Autocorrect Rules")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingAutocorrectRules = false }
                        }
                    }
                }
            }
        }
        .onAppear { loadSettings() }
    }

    private func loadSettings() {
        let descriptor = FetchDescriptor<AppSettings>()
        if let existing = try? modelContext.fetch(descriptor).first {
            settings = existing
        }
    }

    private func saveSettings() {
        let descriptor = FetchDescriptor<AppSettings>()
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.githubPAT = settings.githubPAT
            existing.githubOwner = settings.githubOwner
            existing.githubRepo = settings.githubRepo
            existing.shopifyShopURL = settings.shopifyShopURL
            existing.shopifyAccessToken = settings.shopifyAccessToken
            existing.defaultAuthor = settings.defaultAuthor
            existing.timezone = settings.timezone
            existing.autocorrectRules = settings.autocorrectRules
        } else {
            modelContext.insert(settings)
        }
        try? modelContext.save()
    }
}
