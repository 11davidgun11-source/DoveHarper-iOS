import SwiftUI
import SwiftData
import PhotosUI

struct BookDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var book: BookEntity

    @State private var isEditing = false
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showingDeleteConfirmation = false
    @State private var deleteConfirmationText = ""
    @State private var showingSaveConfirmation = false
    @State private var changedFields: [String] = []
    @State private var needsWorkflow = false
    @State private var showingError = false
    @State private var saved = false

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
    @State private var selectedCoverImage: UIImage?

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

    var body: some View {
        Group {
            if isEditing {
                editForm
            } else {
                readOnlyView
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isEditing {
                    HStack(spacing: 16) {
                        Button("Cancel") {
                            exitEditMode()
                        }
                        .disabled(isSaving)

                        Button("Save") {
                            Task { await performSave() }
                        }
                        .disabled(isSaving)
                    }
                } else {
                    Button("Edit") {
                        enterEditMode()
                    }
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
            Button("Cancel", role: .cancel) {
                deleteConfirmationText = ""
            }
        } message: {
            Text("This will remove the book from the live site. Type DELETE to confirm.")
        }
        .alert("Confirm Changes", isPresented: $showingSaveConfirmation) {
            Button("Save", role: .destructive) {
                Task { await executeSave() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            VStack(alignment: .leading, spacing: 4) {
                if needsWorkflow {
                    Text("⚠️ These changes will regenerate EPUB/PDF and update the live site:")
                        .font(.headline)
                } else {
                    Text("These changes will update the live site:")
                        .font(.headline)
                }
                ForEach(changedFields, id: \.self) { field in
                    Text("• \(field)")
                }
                Text("")
                if needsWorkflow {
                    Text("A GitHub Action will run to regenerate EPUB and PDF samples.")
                }
                Text("Continue?")
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .onChange(of: selectedCoverImage) { _, newValue in
            if let image = newValue {
                editCoverImage = image
                coverChanged = true
            }
        }
    }

    // MARK: - Read-Only View

    private var readOnlyView: some View {
        List {
            Section {
                if let url = book.liveURL {
                    Button {
                        UIApplication.shared.open(URL(string: url)!)
                    } label: {
                        HStack {
                            Image(systemName: "arrow.up.right.square")
                            Text("View Live Page")
                        }
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

                if !book.primaryCheckoutURL.isEmpty {
                    Button {
                        UIApplication.shared.open(URL(string: book.primaryCheckoutURL)!)
                    } label: {
                        HStack {
                            Image(systemName: "bag.fill")
                            Text("View Shopify Product")
                        }
                    }
                }
            }

            Section("Shopify Product URL") {
                if book.primaryCheckoutURL.isEmpty {
                    Text("No product URL set.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(book.primaryCheckoutURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Section("Info") {
                LabeledContent("Title", value: book.title)
                LabeledContent("Slug", value: book.slug)
                LabeledContent("Author", value: book.author)
                LabeledContent("Series", value: book.series)
                if !book.seriesOrder.isEmpty {
                    LabeledContent("Series Order", value: book.seriesOrder)
                }
                LabeledContent("Word Count", value: "\(book.wordCount)")
                LabeledContent("Release Date", value: book.releaseDate)
                LabeledContent("Status", value: book.status)
            }

            Section("Classification") {
                if !book.tropes.isEmpty {
                    FlowLayout(title: "Tropes", items: book.tropes)
                }
                if !book.themes.isEmpty {
                    FlowLayout(title: "Themes", items: book.themes)
                }
                if !book.contentNotes.isEmpty {
                    FlowLayout(title: "Content Notes", items: book.contentNotes)
                }
                if !book.forFansOf.isEmpty {
                    FlowLayout(title: "For Fans Of", items: book.forFansOf)
                }
            }

            Section("Pricing") {
                HStack {
                    Text("Price:")
                    Text(book.isFree ? "Free" : (book.priceLabel.isEmpty ? "Not set" : book.priceLabel))
                }
            }

            Section("Description") {
                if !book.shortDescription.isEmpty {
                    Text(book.shortDescription)
                        .font(.subheadline)
                }
                Text(book.descriptionText)
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
                TextField("Slug", text: .constant(book.slug))
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
                } else if book.manuscriptPath == nil {
                    Button {
                        Task { await fetchManuscriptFromGitHub() }
                    } label: {
                        Label("Fetch Manuscript from GitHub", systemImage: "arrow.down.circle")
                    }
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
        editTitle = book.title
        editAuthor = book.author
        editSeries = book.series
        editSeriesOrder = book.seriesOrder
        editReleaseDate = book.releaseDate
        editShortDescription = book.shortDescription
        editDescriptionText = book.descriptionText
        editPriceLabel = book.priceLabel
        editIsFree = book.isFree
        editIsLatestRelease = book.isLatestRelease
        editIsNovella = book.isNovella
        editPrimaryCheckoutURL = book.primaryCheckoutURL
        editCheckoutProviderLabel = book.checkoutProviderLabel
        editTropes = book.tropes
        editThemes = book.themes
        editForFansOf = book.forFansOf
        editContentNotes = book.contentNotes
        editTickerQuotes = book.tickerQuotes

        // Snapshot originals
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

        // Load manuscript from local path if available
        if let path = book.manuscriptPath,
           let data = FileManager.default.contents(atPath: path),
           let text = String(data: data, encoding: .utf8) {
            editManuscriptText = text
        }

        // Load cover from local path if available, otherwise fetch from GitHub
        if let path = book.coverImagePath,
           let data = FileManager.default.contents(atPath: path),
           let uiImage = UIImage(data: data) {
            editCoverImage = uiImage
        } else {
            fetchCoverFromGitHub()
        }

        isEditing = true
    }

    private func exitEditMode() {
        isEditing = false
        saveError = nil
        manuscriptChanged = false
        coverChanged = false
    }

    // MARK: - Change Detection

    private func computeChanges() -> (needsWorkflow: Bool, fields: [String]) {
        var siteFields: [String] = []
        var workflowFields: [String] = []

        if editTitle != origTitle { workflowFields.append("Title") }
        if editAuthor != origAuthor { workflowFields.append("Author") }
        if manuscriptChanged { workflowFields.append("Manuscript") }
        if coverChanged { workflowFields.append("Cover Image") }

        if editSeries != origSeries { siteFields.append("Series") }
        if editSeriesOrder != origSeriesOrder { siteFields.append("Series Order") }
        if editReleaseDate != origReleaseDate { siteFields.append("Release Date") }
        if editIsLatestRelease != origIsLatestRelease { siteFields.append("Latest Release") }
        if editIsNovella != origIsNovella { siteFields.append("Novella") }
        if editShortDescription != origShortDescription { siteFields.append("Short Description") }
        if editDescriptionText != origDescriptionText { siteFields.append("Description") }
        if editPriceLabel != origPriceLabel { siteFields.append("Price") }
        if editIsFree != origIsFree { siteFields.append("Free/Paid") }
        if editPrimaryCheckoutURL != origPrimaryCheckoutURL { siteFields.append("Checkout URL") }
        if editCheckoutProviderLabel != origCheckoutProviderLabel { siteFields.append("Checkout Provider") }
        if editTropes != origTropes { siteFields.append("Tropes") }
        if editThemes != origThemes { siteFields.append("Themes") }
        if editContentNotes != origContentNotes { siteFields.append("Content Notes") }
        if editForFansOf != origForFansOf { siteFields.append("For Fans Of") }
        if editTickerQuotes != origTickerQuotes { siteFields.append("Ticker Quotes") }

        let allChanged = workflowFields + siteFields
        let needs = !workflowFields.isEmpty
        return (needs, allChanged)
    }

    // MARK: - Save

    private func performSave() async {
        guard let settings = allSettings.first, !settings.githubPAT.isEmpty else {
            saveError = "GitHub credentials not configured."
            showingError = true
            return
        }

        let (needsWF, fields) = computeChanges()
        guard !fields.isEmpty else {
            saveError = "No changes detected."
            showingError = true
            return
        }

        changedFields = fields
        needsWorkflow = needsWF
        showingSaveConfirmation = true
    }

    private func executeSave() async {
        guard let settings = allSettings.first, !settings.githubPAT.isEmpty else {
            saveError = "GitHub credentials not configured."
            showingError = true
            return
        }

        isSaving = true
        defer { isSaving = false }

        let github = GitHubService()

        do {
            // Push manuscript if changed
            if manuscriptChanged, !editManuscriptText.isEmpty {
                let manuscriptData = editManuscriptText.data(using: .utf8)!
                try await github.pushFile(
                    owner: settings.githubOwner,
                    repo: settings.githubRepo,
                    path: "dove-harper-site/manuscripts/\(book.slug).md",
                    content: manuscriptData,
                    message: "Update manuscript for \(book.title)",
                    pat: settings.githubPAT
                )
            }

            // Push cover if changed
            if coverChanged, let cover = editCoverImage,
               let jpegData = cover.jpegData(compressionQuality: 0.9) {
                try await github.pushFile(
                    owner: settings.githubOwner,
                    repo: settings.githubRepo,
                    path: "dove-harper-site/public/assets/img/covers/\(book.slug)-cover.jpg",
                    content: jpegData,
                    message: "Update cover for \(book.title)",
                    pat: settings.githubPAT
                )
            }

            // Always push book JSON
            applyEditsToBook()
            let bookJSON = book.toBookJSON()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(bookJSON)

            try await github.pushFile(
                owner: settings.githubOwner,
                repo: settings.githubRepo,
                path: "dove-harper-site/content/books/\(book.slug).json",
                content: jsonData,
                message: "Update \(book.title)",
                pat: settings.githubPAT
            )

            // Save locally
            if manuscriptChanged, !editManuscriptText.isEmpty {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let manuscriptURL = docs.appendingPathComponent("\(book.slug).md")
                if let data = editManuscriptText.data(using: .utf8) {
                    try? data.write(to: manuscriptURL)
                    book.manuscriptPath = manuscriptURL.path
                }
            }
            if coverChanged, let cover = editCoverImage {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let coverURL = docs.appendingPathComponent("\(book.slug)-cover.jpg")
                if let jpegData = cover.jpegData(compressionQuality: 0.9) {
                    try? jpegData.write(to: coverURL)
                    book.coverImagePath = coverURL.path
                }
            }

            try modelContext.save()

            // Monitor workflow if content changed
            if needsWorkflow {
                let conversion = ConversionService()
                _ = try await conversion.triggerAndMonitorConversion(
                    owner: settings.githubOwner,
                    repo: settings.githubRepo,
                    slug: book.slug,
                    pat: settings.githubPAT,
                    onStatus: { _ in }
                )
            }

            // Success
            await MainActor.run {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }
            withAnimation { saved = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { saved = false }
            }
            isEditing = false

        } catch {
            saveError = error.localizedDescription
            showingError = true
        }
    }

    private func applyEditsToBook() {
        book.title = editTitle
        book.author = editAuthor
        book.series = editSeries
        book.seriesOrder = editSeriesOrder
        book.releaseDate = editReleaseDate
        book.shortDescription = editShortDescription
        book.descriptionText = editDescriptionText
        book.priceLabel = editPriceLabel
        book.isFree = editIsFree
        book.isLatestRelease = editIsLatestRelease
        book.isNovella = editIsNovella
        book.primaryCheckoutURL = editPrimaryCheckoutURL
        book.checkoutProviderLabel = editCheckoutProviderLabel
        book.tropes = editTropes
        book.themes = editThemes
        book.forFansOf = editForFansOf
        book.contentNotes = editContentNotes
        book.tickerQuotes = editTickerQuotes
    }

    // MARK: - Fetch from GitHub

    private func fetchManuscriptFromGitHub() async {
        guard let settings = allSettings.first, !settings.githubPAT.isEmpty else { return }
        let github = GitHubService()
        do {
            let text = try await github.getFileAsString(
                owner: settings.githubOwner,
                repo: settings.githubRepo,
                path: "dove-harper-site/manuscripts/\(book.slug).md",
                pat: settings.githubPAT
            )
            editManuscriptText = text
        } catch {
            print("Could not fetch manuscript: \(error)")
        }
    }

    private func fetchCoverFromGitHub() {
        guard let settings = allSettings.first, !settings.githubPAT.isEmpty else { return }
        let github = GitHubService()
        Task {
            do {
                let data = try await github.getFileContent(
                    owner: settings.githubOwner,
                    repo: settings.githubRepo,
                    path: "dove-harper-site/public/assets/img/covers/\(book.slug)-cover.jpg",
                    pat: settings.githubPAT
                )
                if let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        editCoverImage = uiImage
                    }
                }
            } catch {
                print("Could not fetch cover: \(error)")
            }
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
        guard let settings = allSettings.first else { return }
        guard !settings.githubPAT.isEmpty else { return }

        let github = GitHubService()

        do {
            try await github.deleteFile(
                owner: settings.githubOwner,
                repo: settings.githubRepo,
                path: "dove-harper-site/content/books/\(book.slug).json",
                message: "Delete \(book.title)",
                pat: settings.githubPAT
            )

            try? await github.deleteFile(
                owner: settings.githubOwner,
                repo: settings.githubRepo,
                path: "dove-harper-site/public/assets/img/covers/\(book.slug)-cover.jpg",
                message: "Delete cover for \(book.title)",
                pat: settings.githubPAT
            )

            modelContext.delete(book)
            try modelContext.save()
        } catch {
            print("Delete failed: \(error)")
        }
    }
}
