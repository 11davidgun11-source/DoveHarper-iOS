import SwiftUI
import SwiftData
import PhotosUI

struct BookDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let bookJSON: BookJSON
    @State private var isDraft: Bool

    @State private var isEditing = false
    @State private var isSaving = false
    @State private var publishSuccess = false
    @State private var saveError: String?
    @State private var showingDeleteConfirmation = false
    @State private var deleteConfirmationText = ""
    @State private var showingPublishConfirmation = false
    @State private var changedFields: [String] = []
    @State private var showingError = false

    // Edit state
    @State private var editTitle = ""
    @State private var editAuthor = ""
    @State private var editSeries = ""
    @State private var editSeriesOrder = ""
    @State private var editReleaseDate = ""
    @State private var editShortDescription = ""
    @State private var editDescriptionText = ""
    @State private var editPriceLabel = ""
    @State private var editIsFree = false
    @State private var editIsLatestRelease = true
    @State private var editIsNovella = false
    @State private var editPrimaryCheckoutURL = ""
    @State private var editCheckoutProviderLabel = "Shopify"
    @State private var editTropes: [String] = []
    @State private var editThemes: [String] = []
    @State private var editForFansOf: [String] = []
    @State private var editContentNotes: [String] = []
    @State private var editTickerQuotes: [String] = []
    @State private var editManuscriptText = ""
    @State private var editCoverImage: UIImage?
    @State private var manuscriptChanged = false
    @State private var coverChanged = false

    // File pickers
    @State private var showingManuscriptPicker = false
    @State private var selectedCoverItem: PhotosPickerItem?

    // Original values for change detection
    @State private var origTitle = ""
    @State private var origAuthor = ""
    @State private var origSeries = ""
    @State private var origSeriesOrder = ""
    @State private var origReleaseDate = ""
    @State private var origShortDescription = ""
    @State private var origDescriptionText = ""
    @State private var origPriceLabel = ""
    @State private var origIsFree = false
    @State private var origIsLatestRelease = true
    @State private var origIsNovella = false
    @State private var origPrimaryCheckoutURL = ""
    @State private var origCheckoutProviderLabel = "Shopify"
    @State private var origTropes: [String] = []
    @State private var origThemes: [String] = []
    @State private var origForFansOf: [String] = []
    @State private var origContentNotes: [String] = []
    @State private var origTickerQuotes: [String] = []

    @Query private var allSettings: [AppSettings]
    private var settings: AppSettings? { allSettings.first }
    private let fileManager = BookFileManager()
    private let bookPathPrefix = "dove-harper-site/"

    init(bookJSON: BookJSON, isDraft: Bool = false) {
        self.bookJSON = bookJSON
        self._isDraft = State(initialValue: isDraft)
    }

    var body: some View {
        Group {
            if isEditing {
                editForm
            } else {
                readOnlyView
            }
        }
        .navigationTitle(bookJSON.title)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isEditing {
                    HStack(spacing: 16) {
                        Button("Cancel") { exitEditMode() }
                            .disabled(isSaving)

                        Button("Save Locally") {
                            Task { await saveDraftLocally() }
                        }
                        .disabled(isSaving)

                        Button("Publish") {
                            computeChanges()
                            showingPublishConfirmation = true
                        }
                        .disabled(isSaving)
                        .bold()
                    }
                } else {
                    Button("Edit") { enterEditMode() }
                }
            }
        }
        .alert("Delete Book", isPresented: $showingDeleteConfirmation) {
            TextField("Type DELETE to confirm", text: $deleteConfirmationText)
            Button("Delete", role: .destructive) {
                if deleteConfirmationText == "DELETE" {
                    Task { await deleteBook() }
                }
            }
            .disabled(deleteConfirmationText != "DELETE")
            Button("Cancel", role: .cancel) { deleteConfirmationText = "" }
        } message: {
            Text("This will remove the book from the live site. Type DELETE to confirm.")
        }
        .alert("Publish to GitHub", isPresented: $showingPublishConfirmation) {
            Button("Publish", role: .destructive) {
                Task { await publishToGitHub() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            VStack(alignment: .leading, spacing: 4) {
                Text("These changes will be committed to GitHub:")
                    .font(.headline)
                ForEach(changedFields, id: \.self) { field in
                    Text("• \(field)")
                }
                Text("")
                Text("A single atomic commit will be created. A GitHub Action may run to regenerate EPUB/PDF.")
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .alert("Published!", isPresented: .constant(publishSuccess)) {
            Button("OK") {
                publishSuccess = false
                isEditing = false
            }
        } message: {
            Text("Changes pushed to GitHub. The site will update shortly.")
        }
        .onChange(of: selectedCoverItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    editCoverImage = uiImage
                    coverChanged = true
                }
            }
        }
    }

    // MARK: - Read-Only View

    private var readOnlyView: some View {
        List {
            Section {
                Button {
                    UIApplication.shared.open(URL(string: "https://doveharperauthor.com/books/\(bookJSON.slug)/")!)
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.right.square")
                        Text("View Live Page")
                    }
                }

                Button {
                    let shopURL = URL(string: "https://doveharpershop.myshopify.com/admin/products/new")!
                    UIApplication.shared.open(shopURL)
                } label: {
                    HStack {
                        Image(systemName: "cart.badge.plus")
                        Text("Open Shopify — Create Product")
                    }
                }

                if !bookJSON.primaryCheckoutURL.isEmpty {
                    Button {
                        UIApplication.shared.open(URL(string: bookJSON.primaryCheckoutURL)!)
                    } label: {
                        HStack {
                            Image(systemName: "bag.fill")
                            Text("View Shopify Product")
                        }
                    }
                }
            }

            Section("Shopify Product URL") {
                if bookJSON.primaryCheckoutURL.isEmpty {
                    Text("No product URL set.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(bookJSON.primaryCheckoutURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Section("Info") {
                LabeledContent("Title", value: bookJSON.title)
                LabeledContent("Slug", value: bookJSON.slug)
                LabeledContent("Author", value: bookJSON.author)
                LabeledContent("Series", value: bookJSON.series)
                if let order = bookJSON.seriesOrder, !order.isEmpty {
                    LabeledContent("Series Order", value: order)
                }
                LabeledContent("Word Count", value: "\(bookJSON.wordCount)")
                LabeledContent("Release Date", value: bookJSON.releaseDate)
                LabeledContent("Status", value: bookJSON.status)
            }

            Section("Classification") {
                if !bookJSON.tropes.isEmpty {
                    FlowLayout(title: "Tropes", items: bookJSON.tropes)
                }
                if !bookJSON.themes.isEmpty {
                    FlowLayout(title: "Themes", items: bookJSON.themes)
                }
                if !bookJSON.contentNotes.isEmpty {
                    let notes = bookJSON.contentNotes.components(separatedBy: ", ")
                    FlowLayout(title: "Content Notes", items: notes)
                }
                if !bookJSON.forFansOf.isEmpty {
                    FlowLayout(title: "For Fans Of", items: bookJSON.forFansOf)
                }
            }

            Section("Pricing") {
                HStack {
                    Text("Price:")
                    Text(bookJSON.isFree ? "Free" : (bookJSON.priceLabel.isEmpty ? "Not set" : bookJSON.priceLabel))
                }
            }

            Section("Description") {
                if !bookJSON.shortDescription.isEmpty {
                    Text(bookJSON.shortDescription)
                        .font(.subheadline)
                }
                Text(bookJSON.description)
                    .font(.caption)
            }

            Section {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Book", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Edit Form

    private var editForm: some View {
        Form {
            Section("Basic Info") {
                TextField("Title", text: $editTitle)
                TextField("Author", text: $editAuthor)
                TextField("Slug", text: .constant(bookJSON.slug))
                    .foregroundStyle(.secondary)
                    .disabled(true)
                TextField("Series", text: $editSeries)
                TextField("Series Order", text: $editSeriesOrder)
                    .keyboardType(.numberPad)
                Toggle("Novella", isOn: $editIsNovella)
            }

            Section("Release") {
                TextField("Release Date (YYYY-MM-DD)", text: $editReleaseDate)
                Toggle("Latest Release", isOn: $editIsLatestRelease)
            }

            Section("Classification") {
                TagInputView(
                    tags: $editTropes,
                    placeholder: "Add trope...",
                    autocorrectRules: settings?.autocorrectRules ?? [:]
                )
                TagInputView(
                    tags: $editThemes,
                    placeholder: "Add theme...",
                    autocorrectRules: settings?.autocorrectRules ?? [:]
                )
                TagInputView(
                    tags: $editContentNotes,
                    placeholder: "Add content note...",
                    autocorrectRules: settings?.autocorrectRules ?? [:]
                )
                TagInputView(
                    tags: $editForFansOf,
                    placeholder: "Add author...",
                    autocorrectRules: settings?.autocorrectRules ?? [:]
                )
                TagInputView(
                    tags: $editTickerQuotes,
                    placeholder: "Add ticker quote...",
                    autocorrectRules: settings?.autocorrectRules ?? [:]
                )
            }

            Section("Pricing") {
                Toggle("Free Book", isOn: $editIsFree)
                if !editIsFree {
                    TextField("Price (e.g. $4.99)", text: $editPriceLabel)
                }
                TextField("Shopify Checkout URL", text: $editPrimaryCheckoutURL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                TextField("Checkout Provider", text: $editCheckoutProviderLabel)
            }

            Section("Description") {
                TextField("Short Description (100-180 chars)", text: $editShortDescription, axis: .vertical)
                    .lineLimit(2...4)
                TextField("Description (markdown)", text: $editDescriptionText, axis: .vertical)
                    .lineLimit(6...12)
            }

            Section("Cover Image") {
                if let editCoverImage {
                    Image(uiImage: editCoverImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .cornerRadius(8)
                }

                PhotosPicker(selection: $selectedCoverItem, matching: .images) {
                    Label(editCoverImage == nil ? "Select Cover Image" : "Change Cover", systemImage: "photo")
                }
            }

            Section("Manuscript") {
                if !editManuscriptText.isEmpty {
                    let wordCount = editManuscriptText.split(separator: " ").count
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.green)
                        Text("\(wordCount) words loaded")
                            .foregroundStyle(.green)
                    }
                }

                Button {
                    Task { await fetchManuscriptFromGitHub() }
                } label: {
                    Label("Fetch Manuscript from GitHub", systemImage: "arrow.down.circle")
                }

                Button {
                    showingManuscriptPicker = true
                } label: {
                    Label(editManuscriptText.isEmpty ? "Import Manuscript" : "Replace Manuscript", systemImage: "doc.badge.plus")
                }
            }

            Section {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Book", systemImage: "trash")
                }
            }
        }
        .fileImporter(
            isPresented: $showingManuscriptPicker,
            allowedContentTypes: [.plainText, .pdf],
            allowsMultipleSelection: false
        ) { result in
            handleManuscriptImport(result)
        }
    }

    // MARK: - Edit Mode

    private func enterEditMode() {
        editTitle = bookJSON.title
        editAuthor = bookJSON.author
        editSeries = bookJSON.series
        editSeriesOrder = bookJSON.seriesOrder ?? ""
        editReleaseDate = bookJSON.releaseDate
        editShortDescription = bookJSON.shortDescription
        editDescriptionText = bookJSON.description
        editPriceLabel = bookJSON.priceLabel
        editIsFree = bookJSON.isFree
        editIsLatestRelease = bookJSON.isLatestRelease
        editIsNovella = bookJSON.isNovella
        editPrimaryCheckoutURL = bookJSON.primaryCheckoutURL
        editCheckoutProviderLabel = bookJSON.checkoutProviderLabel
        editTropes = bookJSON.tropes
        editThemes = bookJSON.themes
        editForFansOf = bookJSON.forFansOf
        editContentNotes = bookJSON.contentNotes.isEmpty ? [] : bookJSON.contentNotes.components(separatedBy: ", ")
        editTickerQuotes = bookJSON.tickerQuotes

        origTitle = editTitle
        origAuthor = editAuthor
        origSeries = editSeries
        origSeriesOrder = editSeriesOrder
        origReleaseDate = editReleaseDate
        origShortDescription = editShortDescription
        origDescriptionText = editDescriptionText
        origPriceLabel = editPriceLabel
        origIsFree = editIsFree
        origIsLatestRelease = editIsLatestRelease
        origIsNovella = editIsNovella
        origPrimaryCheckoutURL = editPrimaryCheckoutURL
        origCheckoutProviderLabel = editCheckoutProviderLabel
        origTropes = editTropes
        origThemes = editThemes
        origForFansOf = editForFansOf
        origContentNotes = editContentNotes
        origTickerQuotes = editTickerQuotes

        manuscriptChanged = false
        coverChanged = false

        isEditing = true
    }

    private func exitEditMode() {
        isEditing = false
        saveError = nil
        manuscriptChanged = false
        coverChanged = false
    }

    // MARK: - Change Detection

    private func computeChanges() {
        var fields: [String] = []

        if editTitle != origTitle { fields.append("Title") }
        if editAuthor != origAuthor { fields.append("Author") }
        if editSeries != origSeries { fields.append("Series") }
        if editSeriesOrder != origSeriesOrder { fields.append("Series Order") }
        if editReleaseDate != origReleaseDate { fields.append("Release Date") }
        if editIsLatestRelease != origIsLatestRelease { fields.append("Latest Release") }
        if editIsNovella != origIsNovella { fields.append("Novella") }
        if editShortDescription != origShortDescription { fields.append("Short Description") }
        if editDescriptionText != origDescriptionText { fields.append("Description") }
        if editPriceLabel != origPriceLabel { fields.append("Price") }
        if editIsFree != origIsFree { fields.append("Free/Paid") }
        if editPrimaryCheckoutURL != origPrimaryCheckoutURL { fields.append("Checkout URL") }
        if editCheckoutProviderLabel != origCheckoutProviderLabel { fields.append("Checkout Provider") }
        if editTropes != origTropes { fields.append("Tropes") }
        if editThemes != origThemes { fields.append("Themes") }
        if editContentNotes != origContentNotes { fields.append("Content Notes") }
        if editForFansOf != origForFansOf { fields.append("For Fans Of") }
        if editTickerQuotes != origTickerQuotes { fields.append("Ticker Quotes") }
        if manuscriptChanged { fields.append("Manuscript") }
        if coverChanged { fields.append("Cover Image") }

        changedFields = fields
    }

    // MARK: - Save Draft Locally

    private func saveDraftLocally() async {
        isSaving = true
        defer { isSaving = false }

        do {
            let bookJSON = buildBookJSON()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let coverData = editCoverImage?.jpegData(compressionQuality: 0.9)
            try fileManager.saveDraft(book: bookJSON, manuscript: editManuscriptText.isEmpty ? nil : editManuscriptText, coverData: coverData)
            print("[BookDetailView] Draft saved locally for \(bookJSON.slug)")
        } catch {
            saveError = "Failed to save draft: \(error.localizedDescription)"
            showingError = true
        }
    }

    // MARK: - Publish to GitHub (atomic commit via Git Data API)

    private func publishToGitHub() async {
        guard let settings = allSettings.first, !settings.githubPAT.isEmpty else {
            saveError = "GitHub credentials not configured."
            showingError = true
            return
        }

        isSaving = true
        defer { isSaving = false }

        let git = GitService()
        let slug = bookJSON.slug
        var files: [(path: String, data: Data)] = []

        do {
            // Build the updated book JSON
            let updatedBook = buildBookJSON()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let bookData = try encoder.encode(updatedBook)
            files.append((path: "\(bookPathPrefix)content/books/\(slug).json", data: bookData))
            print("[Publish] Book JSON ready (\(bookData.count) bytes)")

            // Add manuscript if changed
            if manuscriptChanged, !editManuscriptText.isEmpty,
               let manuscriptData = editManuscriptText.data(using: .utf8) {
                files.append((path: "\(bookPathPrefix)manuscripts/\(slug).md", data: manuscriptData))
                print("[Publish] Manuscript ready (\(manuscriptData.count) bytes)")
            }

            // Add cover if changed
            if coverChanged, let cover = editCoverImage,
               let jpegData = cover.jpegData(compressionQuality: 0.9) {
                files.append((path: "\(bookPathPrefix)public/assets/img/covers/\(slug)-cover.jpg", data: jpegData))
                print("[Publish] Cover ready (\(jpegData.count) bytes)")
            }

            // Atomic commit
            let commitSHA = try await git.commitChanges(
                owner: settings.githubOwner,
                repo: settings.githubRepo,
                branch: "main",
                message: "Update \(updatedBook.title)",
                files: files,
                pat: settings.githubPAT
            )

            print("[Publish] Committed: \(commitSHA.prefix(8))")
            publishSuccess = true

        } catch {
            print("[Publish] FAILED: \(error)")
            saveError = "\(error)"
            showingError = true
        }
    }

    // MARK: - Build BookJSON from edits

    private func buildBookJSON() -> BookJSON {
        BookJSON(
            slug: bookJSON.slug,
            title: editTitle,
            author: editAuthor,
            catalogStatus: bookJSON.catalogStatus,
            seriesType: editSeriesOrder.isEmpty ? "standalone" : "series",
            series: editSeries,
            seriesOrder: editSeriesOrder.isEmpty ? nil : editSeriesOrder,
            isNovella: editIsNovella,
            isBundle: bookJSON.isBundle,
            bundleMembers: bookJSON.bundleMembers,
            releaseDate: editReleaseDate,
            wordCount: bookJSON.wordCount,
            isLatestRelease: editIsLatestRelease,
            tropes: editTropes,
            themes: editThemes,
            forFansOf: editForFansOf,
            tickerQuotes: editTickerQuotes,
            formats: bookJSON.formats,
            isFree: editIsFree,
            primaryCheckoutURL: editPrimaryCheckoutURL,
            backupCheckoutURL: bookJSON.backupCheckoutURL,
            checkoutProviderLabel: editCheckoutProviderLabel,
            backupCheckoutProviderLabel: bookJSON.backupCheckoutProviderLabel,
            priceLabel: editPriceLabel,
            formatsIncluded: bookJSON.formatsIncluded,
            sampleEPUBURL: bookJSON.sampleEPUBURL,
            samplePDFURL: bookJSON.samplePDFURL,
            sampleDOCXURL: bookJSON.sampleDOCXURL,
            coverImage: bookJSON.coverImage,
            shortDescription: editShortDescription,
            description: editDescriptionText,
            contentNotes: editContentNotes.joined(separator: ", "),
            status: bookJSON.status,
            sourceMarkdown: bookJSON.sourceMarkdown
        )
    }

    // MARK: - Fetch from GitHub

    private func fetchManuscriptFromGitHub() async {
        guard let settings = allSettings.first, !settings.githubPAT.isEmpty else { return }
        let github = GitHubService()
        do {
            let text = try await github.getFileAsString(
                owner: settings.githubOwner,
                repo: settings.githubRepo,
                path: "\(bookPathPrefix)manuscripts/\(bookJSON.slug).md",
                pat: settings.githubPAT
            )
            editManuscriptText = text
        } catch {
            print("Could not fetch manuscript: \(error)")
        }
    }

    // MARK: - File Import

    private func handleManuscriptImport(_ result: Result<[URL], Error>) {
        guard let urls = try? result.get(),
              let url = urls.first else { return }

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        if let data = FileManager.default.contents(atPath: url.path),
           let text = String(data: data, encoding: .utf8) {
            editManuscriptText = text
            manuscriptChanged = true
        }
    }

    // MARK: - Delete

    private func deleteBook() async {
        guard let settings = allSettings.first, !settings.githubPAT.isEmpty else { return }

        let github = GitHubService()

        do {
            // Delete JSON
            try await github.deleteFile(
                owner: settings.githubOwner,
                repo: settings.githubRepo,
                path: "\(bookPathPrefix)content/books/\(bookJSON.slug).json",
                message: "Delete \(bookJSON.title)",
                pat: settings.githubPAT
            )

            // Delete cover (best effort)
            try? await github.deleteFile(
                owner: settings.githubOwner,
                repo: settings.githubRepo,
                path: "\(bookPathPrefix)public/assets/img/covers/\(bookJSON.slug)-cover.jpg",
                message: "Delete cover for \(bookJSON.title)",
                pat: settings.githubPAT
            )

            // Delete local draft if exists
            try? fileManager.deleteDraft(slug: bookJSON.slug)

            dismiss()
        } catch {
            print("Delete failed: \(error)")
            saveError = "\(error)"
            showingError = true
        }
    }
}
