import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allSettings: [AppSettings]
    @State private var pat = ""
    @State private var owner = ""
    @State private var repo = ""
    @State private var defaultAuthor = ""
    @State private var timezone = ""
    @State private var showingAutocorrectRules = false
    @State private var newRulePattern = ""
    @State private var newRuleReplacement = ""
    @State private var saved = false
    @State private var rules: [String: String] = [:]

    private let timezones = [
        "UTC", "America/New_York", "America/Chicago", "America/Denver",
        "America/Los_Angeles", "Europe/London", "Europe/Paris", "Europe/Berlin",
        "Europe/Lisbon", "Asia/Tokyo", "Asia/Shanghai", "Australia/Sydney"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Configure your GitHub repository to publish books. After publishing, open Shopify to create the product, then paste the product URL back into the book.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("GitHub") {
                    TextField("Personal Access Token", text: $pat)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                    TextField("Owner", text: $owner)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    TextField("Repository", text: $repo)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }

                Section {
                    TextField("Default Author Name", text: $defaultAuthor)
                    Picker("Timezone", selection: $timezone) {
                        ForEach(timezones, id: \.self) { tz in
                            Text(tz.replacingOccurrences(of: "/", with: " — ")).tag(tz)
                        }
                    }
                } header: {
                    Text("Defaults")
                } footer: {
                    Text("Author name used for new books. Timezone affects scheduled publish times.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Text Autocorrect") {
                    Button {
                        showingAutocorrectRules = true
                    } label: {
                        HStack {
                            Text("Manage Rules")
                            Spacer()
                            Text("\(rules.count) rules")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                        }
                    }
                }

                Section {
                    Button {
                        saveSettings()
                        withAnimation { saved = true }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { saved = false }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if saved {
                                Label("Saved!", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .transition(.scale.combined(with: .opacity))
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
            .dismissKeyboardOnTap()
            .sheet(isPresented: $showingAutocorrectRules) {
                NavigationStack {
                    List {
                        ForEach(Array(rules.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                            HStack {
                                Text(key).foregroundStyle(.secondary)
                                Image(systemName: "arrow.right")
                                Text(value)
                            }
                        }
                        .onDelete { indexSet in
                            let sorted = rules.sorted(by: { $0.key < $1.key })
                            for index in indexSet {
                                rules.removeValue(forKey: sorted[index].key)
                            }
                        }

                        Section("Add Rule") {
                            TextField("Pattern", text: $newRulePattern)
                            TextField("Replacement", text: $newRuleReplacement)
                            Button("Add Rule") {
                                if !newRulePattern.isEmpty && !newRuleReplacement.isEmpty {
                                    rules[newRulePattern.lowercased()] = newRuleReplacement
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
            pat = existing.githubPAT
            owner = existing.githubOwner
            repo = existing.githubRepo
            defaultAuthor = existing.defaultAuthor
            timezone = existing.timezone
            rules = existing.autocorrectRules
        }
    }

    private func saveSettings() {
        let descriptor = FetchDescriptor<AppSettings>()
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.githubPAT = pat
            existing.githubOwner = owner
            existing.githubRepo = repo
            existing.defaultAuthor = defaultAuthor
            existing.timezone = timezone
            existing.autocorrectRules = rules
        } else {
            let s = AppSettings()
            s.githubPAT = pat
            s.githubOwner = owner
            s.githubRepo = repo
            s.defaultAuthor = defaultAuthor
            s.timezone = timezone
            s.autocorrectRules = rules
            modelContext.insert(s)
        }
        do {
            try modelContext.save()
        } catch {
            print("[Settings] Save failed: \(error)")
        }
    }
}
