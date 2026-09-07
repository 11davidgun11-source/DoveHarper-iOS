import SwiftUI
import SwiftData

struct BookListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<BookEntity> { $0.isLocalDraft == false }) private var publishedBooks: [BookEntity]
    @Query(filter: #Predicate<BookEntity> { $0.isLocalDraft == true }) private var drafts: [BookEntity]
    @State private var showingNewBook = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var lastSynced: Date?
    @State private var patMissing = false

    private var allBooks: [BookEntity] {
        drafts + publishedBooks
    }

    private var filteredBooks: [BookEntity] {
        if searchText.isEmpty { return allBooks }
        return allBooks.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.slug.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading books from site...")
                } else if filteredBooks.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No books yet")
                            .font(.title2)
                        if patMissing {
                            Text("Configure your GitHub PAT in Settings to load books")
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
                        if let lastSynced {
                            Section {
                                HStack {
                                    Text("Synced \(lastSynced.formatted(.relative(presentation: .named)))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if !drafts.isEmpty {
                            Section("Drafts") {
                                ForEach(drafts) { book in
                                    NavigationLink(destination: BookEditorView(book: book)) {
                                        BookRow(book: book)
                                    }
                                }
                                .onDelete { indexSet in
                                    for index in indexSet {
                                        let book = drafts[index]
                                        modelContext.delete(book)
                                    }
                                    try? modelContext.save()
                                }
                            }
                        }

                        if !publishedBooks.isEmpty {
                            Section("Published") {
                                ForEach(publishedBooks) { book in
                                    NavigationLink(destination: BookDetailView(book: book)) {
                                        BookRow(book: book)
                                    }
                                }
                            }
                        }
                    }
                    .refreshable {
                        await refreshBooks()
                    }
                }
            }
            .navigationTitle("Dove Harper")
            .searchable(text: $searchText, prompt: "Search books...")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await refreshBooks() }
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
            .task { await refreshBooks() }
        }
    }

    private func refreshBooks() async {
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

            print("[BookListView] Fetched \(books.count) books from GitHub")

            // Clear all existing books to remove stale drafts
            let allBooksDescriptor = FetchDescriptor<BookEntity>()
            let allExisting = try modelContext.fetch(allBooksDescriptor)
            for old in allExisting {
                modelContext.delete(old)
            }

            // Insert fresh data from GitHub
            for bookJSON in books {
                let entity = createEntity(from: bookJSON)
                modelContext.insert(entity)
                print("[BookListView] Inserted book: \(bookJSON.title)")
            }

            try modelContext.save()
            lastSynced = Date()
            print("[BookListView] Save successful, lastSynced set")
        } catch {
            print("[BookListView] Error: \(error.localizedDescription)")
            errorMessage = "Failed to load books: \(error.localizedDescription)"
        }
    }

    private func createEntity(from book: BookJSON) -> BookEntity {
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
        entity.contentNotes = book.contentNotes.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        entity.tickerQuotes = book.tickerQuotes
        entity.shortDescription = book.shortDescription
        entity.descriptionText = book.description
        entity.priceLabel = book.priceLabel
        entity.isFree = book.isFree
        entity.status = book.status
        entity.primaryCheckoutURL = book.primaryCheckoutURL
        entity.checkoutProviderLabel = book.checkoutProviderLabel
        entity.isLocalDraft = false
        entity.liveURL = "https://doveharperauthor.com/books/\(book.slug)/"
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
        entity.contentNotes = book.contentNotes.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        entity.tickerQuotes = book.tickerQuotes
        entity.shortDescription = book.shortDescription
        entity.descriptionText = book.description
        entity.priceLabel = book.priceLabel
        entity.isFree = book.isFree
        entity.status = book.status
        entity.primaryCheckoutURL = book.primaryCheckoutURL
        entity.checkoutProviderLabel = book.checkoutProviderLabel
        entity.liveURL = "https://doveharperauthor.com/books/\(book.slug)/"
    }
}

struct BookRow: View {
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
                if book.isLocalDraft {
                    Text("Draft")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if let url = book.liveURL, !book.isLocalDraft {
                Link(destination: URL(string: url)!) {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.blue)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    UIApplication.shared.open(URL(string: url)!)
                })
            }
        }
        .padding(.vertical, 4)
    }
}
