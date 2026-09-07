import SwiftUI
import SwiftData

struct BookListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<BookEntity> { $0.isLocalDraft == true }) private var drafts: [BookEntity]
    @State private var liveBooks: [BookJSON] = []
    @State private var showingNewBook = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var lastSynced: Date?
    @State private var patMissing = false

    private var fileManager = BookFileManager()

    private var filteredLive: [BookJSON] {
        if searchText.isEmpty { return liveBooks }
        return liveBooks.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.slug.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredDrafts: [BookEntity] {
        if searchText.isEmpty { return drafts }
        return drafts.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.slug.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading books from site...")
                } else if liveBooks.isEmpty && drafts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No books")
                            .font(.title2)
                        if patMissing {
                            Text("Configure your GitHub PAT in Settings")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        } else {
                            Text("Pull from site or create a new book")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    List {
                        // Live Books — always fetched fresh, empty if offline
                        Section("Live Books") {
                            if liveBooks.isEmpty {
                                Text("No live books found (offline?)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(filteredLive, id: \.slug) { book in
                                    NavigationLink(destination: BookDetailView(
                                        bookJSON: book,
                                        isDraft: false
                                    )) {
                                        LiveBookRow(book: book)
                                    }
                                }
                            }
                        }

                        // Drafts — local files only
                        if !filteredDrafts.isEmpty {
                            Section("Drafts") {
                                ForEach(filteredDrafts) { book in
                                    NavigationLink(destination: BookEditorView(book: book)) {
                                        DraftBookRow(book: book)
                                    }
                                }
                                .onDelete { indexSet in
                                    for index in indexSet {
                                        let book = filteredDrafts[index]
                                        try? fileManager.deleteDraft(slug: book.slug)
                                        modelContext.delete(book)
                                    }
                                    try? modelContext.save()
                                }
                            }
                        }
                    }
                    .refreshable {
                        await refreshLiveBooks()
                    }
                }
            }
            .navigationTitle("Dove Harper")
            .searchable(text: $searchText, prompt: "Search books...")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await refreshLiveBooks() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewBook = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewBook) {
                NavigationStack {
                    BookEditorView(book: BookEntity())
                        .navigationTitle("New Book")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .task {
                await refreshLiveBooks()
                loadLocalDrafts()
            }
        }
    }

    // MARK: - Fetch Live Books from GitHub (always fresh, empty if offline)

    private func refreshLiveBooks() async {
        let descriptor = FetchDescriptor<AppSettings>()
        let settings: AppSettings
        do {
            guard let fetched = try modelContext.fetch(descriptor).first else {
                errorMessage = "No settings found. Go to Settings tab."
                return
            }
            settings = fetched
        } catch {
            errorMessage = "Failed to load settings: \(error.localizedDescription)"
            return
        }

        if settings.githubPAT.isEmpty {
            patMissing = true
            errorMessage = "GitHub PAT not configured. Go to Settings tab."
            return
        }

        patMissing = false
        isLoading = true
        defer { isLoading = false }

        do {
            let github = GitHubService()
            let books = try await github.listBooks(
                owner: settings.githubOwner,
                repo: settings.githubRepo,
                pat: settings.githubPAT
            )

            // Always override — clear old live books, insert fresh
            liveBooks = books
            lastSynced = Date()
            print("[BookListView] Loaded \(books.count) live books from GitHub")
        } catch {
            // Offline or error — show empty live books, keep drafts
            liveBooks = []
            let msg = error.localizedDescription
            errorMessage = msg.count > 200 ? String(msg.prefix(200)) + "..." : msg
            print("[BookListView] Live fetch failed: \(msg)")
        }
    }

    // MARK: - Load Local Drafts from File System

    private func loadLocalDrafts() {
        let slugs = fileManager.listDraftSlugs()

        // Remove SwiftData drafts that no longer exist on disk
        let existingSlugs = Set(drafts.map { $0.slug })
        let currentSlugs = Set(slugs)
        for draft in drafts where !currentSlugs.contains(draft.slug) {
            modelContext.delete(draft)
        }

        // Add new or updated drafts
        for slug in slugs {
            if let bookJSON = fileManager.loadDraft(slug: slug) {
                if let existing = drafts.first(where: { $0.slug == slug }) {
                    // Update existing
                    updateEntity(existing, from: bookJSON)
                } else {
                    // Create new
                    let entity = createDraftEntity(from: bookJSON)
                    modelContext.insert(entity)
                }
            }
        }

        try? modelContext.save()
        print("[BookListView] Loaded \(slugs.count) local drafts")
    }

    private func createDraftEntity(from book: BookJSON) -> BookEntity {
        let entity = BookEntity(slug: book.slug, title: book.title, author: book.author)
        entity.series = book.series
        entity.seriesOrder = book.seriesOrder ?? ""
        entity.isNovella = book.isNovella
        entity.releaseDate = book.releaseDate
        entity.wordCount = book.wordCount
        entity.isLatestRelease = book.isLatestRelease
        entity.tropes = book.tropes
        entity.themes = book.themes
        entity.forFansOf = book.forFansOf
        entity.contentNotes = book.contentNotes.isEmpty ? [] : book.contentNotes.components(separatedBy: ", ")
        entity.tickerQuotes = book.tickerQuotes
        entity.shortDescription = book.shortDescription
        entity.descriptionText = book.description
        entity.priceLabel = book.priceLabel
        entity.isFree = book.isFree
        entity.status = book.status
        entity.primaryCheckoutURL = book.primaryCheckoutURL
        entity.checkoutProviderLabel = book.checkoutProviderLabel
        entity.isLocalDraft = true
        return entity
    }

    private func updateEntity(_ entity: BookEntity, from book: BookJSON) {
        entity.title = book.title
        entity.author = book.author
        entity.series = book.series
        entity.seriesOrder = book.seriesOrder ?? ""
        entity.isNovella = book.isNovella
        entity.releaseDate = book.releaseDate
        entity.wordCount = book.wordCount
        entity.isLatestRelease = book.isLatestRelease
        entity.tropes = book.tropes
        entity.themes = book.themes
        entity.forFansOf = book.forFansOf
        entity.contentNotes = book.contentNotes.isEmpty ? [] : book.contentNotes.components(separatedBy: ", ")
        entity.tickerQuotes = book.tickerQuotes
        entity.shortDescription = book.shortDescription
        entity.descriptionText = book.description
        entity.priceLabel = book.priceLabel
        entity.isFree = book.isFree
        entity.status = book.status
        entity.primaryCheckoutURL = book.primaryCheckoutURL
        entity.checkoutProviderLabel = book.checkoutProviderLabel
        entity.isLocalDraft = true
    }
}

// MARK: - Row Views

struct LiveBookRow: View {
    let book: BookJSON

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                HStack(spacing: 8) {
                    Text(book.series)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if book.isFree {
                        Text("Free")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.2))
                            .cornerRadius(4)
                    } else if !book.priceLabel.isEmpty {
                        Text(book.priceLabel)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
            }
            Spacer()
            Link(destination: URL(string: "https://doveharperauthor.com/books/\(book.slug)/")!) {
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}

struct DraftBookRow: View {
    let book: BookEntity

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                HStack(spacing: 8) {
                    Text(book.series)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Draft")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
