import SwiftUI
import SwiftData

struct QueueView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<QueueEntry> { $0.status == "pending" }) private var pendingEntries: [QueueEntry]
    @Query(filter: #Predicate<QueueEntry> { $0.status == "published" }) private var publishedEntries: [QueueEntry]
    @Query private var allBooks: [BookEntity]
    @Query private var allSettings: [AppSettings]

    @State private var showingNewEntry = false
    @State private var selectedBook: BookEntity?
    @State private var scheduledDate = Date()
    @State private var isFiring = false
    @State private var fireProgress: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Scheduled") {
                    if pendingEntries.isEmpty {
                        Text("No scheduled releases")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(pendingEntries) { entry in
                            QueueEntryRow(entry: entry)
                        }
                    }
                }

                Section("Published") {
                    if publishedEntries.isEmpty {
                        Text("No published from queue")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(publishedEntries) { entry in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(entry.bookTitle)
                                        .font(.headline)
                                    Text(entry.scheduledDate.formatted())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }

                if !pendingEntries.isEmpty {
                    Section {
                        Button {
                            Task { await fireAllDue() }
                        } label: {
                            Label("Fire All Due Now", systemImage: "bolt.fill")
                        }
                        .disabled(isFiring)
                    }
                }
            }
            .navigationTitle("Queue")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewEntry = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewEntry) {
                NavigationStack {
                    Form {
                        Section("Book") {
                            Picker("Select Book", selection: $selectedBook) {
                                Text("None").tag(nil as BookEntity?)
                                ForEach(allBooks.filter { $0.isLocalDraft }) { book in
                                    Text(book.title).tag(book as BookEntity?)
                                }
                            }
                        }
                        Section("Schedule") {
                            DatePicker("Release Date", selection: $scheduledDate, displayedComponents: [.date, .hourAndMinute])
                        }
                        Section {
                            Button("Add to Queue") {
                                if let book = selectedBook {
                                    let entry = QueueEntry(
                                        bookSlug: book.slug,
                                        bookTitle: book.title,
                                        scheduledDate: scheduledDate
                                    )
                                    entry.bookJSONString = book.toBookJSON().toJSONString()
                                    if let path = book.manuscriptPath,
                                       let data = FileManager.default.contents(atPath: path) {
                                        entry.manuscriptData = data
                                    }
                                    modelContext.insert(entry)
                                    try? modelContext.save()
                                    showingNewEntry = false
                                }
                            }
                            .disabled(selectedBook == nil)
                        }
                    }
                    .navigationTitle("New Queue Entry")
                    .navigationBarTitleDisplayMode(.inline)
                    .dismissKeyboardOnTap()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Cancel") { showingNewEntry = false }
                        }
                    }
                }
            }
        }
    }

    private func fireAllDue() async {
        guard let settings = allSettings.first else { return }
        guard !settings.githubPAT.isEmpty else { return }

        let now = Date()
        let dueEntries = pendingEntries.filter { $0.scheduledDate <= now }

        for entry in dueEntries {
            await fireEntry(entry, settings: settings)
        }
    }

    private func fireEntry(_ entry: QueueEntry, settings: AppSettings) async {
        isFiring = true
        defer { isFiring = false }

        guard let bookJSONString = entry.bookJSONString,
              let bookData = bookJSONString.data(using: .utf8) else {
            entry.status = "failed"
            try? modelContext.save()
            return
        }

        let github = GitHubService()

        do {
            if let manuscriptData = entry.manuscriptData {
                try await github.pushFile(
                    owner: settings.githubOwner,
                    repo: settings.githubRepo,
                    path: "dove-harper-site/manuscripts/\(entry.bookSlug).md",
                    content: manuscriptData,
                    message: "Add manuscript for \(entry.bookTitle)",
                    pat: settings.githubPAT
                )
            }

            try await github.pushFile(
                owner: settings.githubOwner,
                repo: settings.githubRepo,
                path: "dove-harper-site/content/books/\(entry.bookSlug).json",
                content: bookData,
                message: "Publish \(entry.bookTitle)",
                pat: settings.githubPAT
            )

            entry.status = "published"
            try modelContext.save()
        } catch {
            entry.status = "failed"
            try? modelContext.save()
        }
    }
}

struct QueueEntryRow: View {
    let entry: QueueEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(entry.bookTitle)
                    .font(.headline)
                Text(entry.scheduledDate.formatted())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if entry.scheduledDate <= Date() {
                Text("Ready")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.green.opacity(0.2))
                    .cornerRadius(4)
            } else {
                Text(entry.scheduledDate.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
