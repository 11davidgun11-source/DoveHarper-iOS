import SwiftUI
import SwiftData
import PhotosUI

struct BookEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var book: BookEntity

    @State private var selectedImage: PhotosPickerItem?
    @State private var coverImage: UIImage?
    @State private var manuscriptText = ""
    @State private var showingManuscriptPicker = false
    @State private var showingPublishView = false
    @State private var showingPublishGate = false
    @State private var showingDeleteConfirmation = false
    @State private var deleteConfirmationText = ""
    @State private var errorMessage: String?
    @State private var showingError = false

    @Query private var allSettings: [AppSettings]
    private var settings: AppSettings? { allSettings.first }

    var body: some View {
        Form {
            Section("Basic Info") {
                TextField("Title", text: $book.title)
                    .onChange(of: book.title) { oldValue, newValue in
                        if book.slug.isEmpty || book.slug == slugify(oldValue) {
                            book.slug = slugify(newValue)
                        }
                    }
                TextField("Slug", text: $book.slug)
                    .autocorrectionDisabled()
                TextField("Series", text: $book.series)
                TextField("Series Order", text: $book.seriesOrder)
                    .keyboardType(.numberPad)
                Toggle("Novella", isOn: $book.isNovella)
            }

            Section("Release") {
                DatePicker("Release Date", selection: releaseDateBinding, displayedComponents: .date)
                Toggle("Latest Release", isOn: $book.isLatestRelease)
            }

            Section("Classification") {
                TagInputView(
                    tags: $book.tropes,
                    placeholder: "Add trope...",
                    autocorrectRules: settings?.autocorrectRules ?? [:]
                )
                TagInputView(
                    tags: $book.themes,
                    placeholder: "Add theme...",
                    autocorrectRules: settings?.autocorrectRules ?? [:]
                )
                TagInputView(
                    tags: $book.contentNotes,
                    placeholder: "Add content note...",
                    autocorrectRules: settings?.autocorrectRules ?? [:]
                )
                TagInputView(
                    tags: $book.forFansOf,
                    placeholder: "Add author...",
                    autocorrectRules: settings?.autocorrectRules ?? [:]
                )
                TagInputView(
                    tags: $book.tickerQuotes,
                    placeholder: "Add ticker quote...",
                    autocorrectRules: settings?.autocorrectRules ?? [:]
                )
            }

            Section("Pricing") {
                Toggle("Free Book", isOn: $book.isFree)
                PriceInputView(priceLabel: $book.priceLabel, isFree: $book.isFree)
                if !book.isFree {
                    TextField("Shopify Checkout URL", text: $book.primaryCheckoutURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                }
            }

            Section("Description") {
                TextField("Short Description (100-180 chars)", text: $book.shortDescription, axis: .vertical)
                    .lineLimit(2...4)
                    .onChange(of: book.shortDescription) { _, newValue in
                        book.shortDescription = correctText(newValue)
                    }
                TextField("Description (markdown)", text: $book.descriptionText, axis: .vertical)
                    .lineLimit(6...12)
                    .onChange(of: book.descriptionText) { _, newValue in
                        book.descriptionText = correctText(newValue)
                    }
            }

            Section("Cover Image") {
                if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .cornerRadius(8)
                }

                PhotosPicker(selection: $selectedImage, matching: .images) {
                    Label(coverImage == nil ? "Select Cover Image" : "Change Cover", systemImage: "photo")
                }
                .onChange(of: selectedImage) { _, newValue in
                    Task {
                        if let data = try? await newValue?.loadTransferable(type: Data.self),
                           let uiImage = UIImage(data: data) {
                            coverImage = uiImage
                            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                            let coverURL = docs.appendingPathComponent("\(book.slug)-cover.jpg")
                            if let jpegData = uiImage.jpegData(compressionQuality: 0.9) {
                                try? jpegData.write(to: coverURL)
                                book.coverImagePath = coverURL.path
                            }
                        }
                    }
                }
            }

            Section("Manuscript") {
                if book.manuscriptPath != nil {
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.green)
                        Text("Manuscript loaded")
                            .foregroundStyle(.green)
                    }
                }

                Button {
                    showingManuscriptPicker = true
                } label: {
                    Label(book.manuscriptPath == nil ? "Import Manuscript" : "Replace Manuscript", systemImage: "doc.badge.plus")
                }

                if !manuscriptText.isEmpty {
                    let wordCount = manuscriptText.split(separator: " ").count
                    Text("\(wordCount) words")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    saveDraft()
                } label: {
                    Label("Save Draft", systemImage: "square.and.arrow.down")
                }

                Button {
                    showingPublishGate = true
                } label: {
                    Label("Publish", systemImage: "arrow.up.circle.fill")
                }
                .disabled(book.slug.isEmpty || book.title.isEmpty)
            }

            if book.isLocalDraft {
                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Draft", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle(book.title.isEmpty ? "New Book" : book.title)
        .navigationBarTitleDisplayMode(.inline)
        .dismissKeyboardOnTap()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    saveDraft()
                    dismiss()
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
        .sheet(isPresented: $showingPublishGate) {
            PublishGateView(
                book: book,
                coverImage: coverImage,
                manuscriptText: manuscriptText,
                onPublish: {
                    showingPublishGate = false
                    showingPublishView = true
                },
                onCancel: {
                    showingPublishGate = false
                }
            )
        }
        .fullScreenCover(isPresented: $showingPublishView) {
            PublishView(book: book, coverImage: coverImage, manuscriptText: manuscriptText)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Delete Draft", isPresented: $showingDeleteConfirmation) {
            TextField("Type DELETE to confirm", text: $deleteConfirmationText)
            Button("Delete", role: .destructive) {
                if deleteConfirmationText == "DELETE" {
                    modelContext.delete(book)
                    try? modelContext.save()
                    dismiss()
                }
            }
            .disabled(deleteConfirmationText != "DELETE")
            Button("Cancel", role: .cancel) {
                deleteConfirmationText = ""
            }
        } message: {
            Text("This will permanently delete this draft. Type DELETE to confirm.")
        }
        .onAppear { loadExistingData() }
    }

    private var releaseDateBinding: Binding<Date> {
        Binding(
            get: {
                if let date = ISO8601DateFormatter().date(from: book.releaseDate) {
                    return date
                }
                return Date()
            },
            set: { newDate in
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                book.releaseDate = formatter.string(from: newDate)
            }
        )
    }

    private func loadExistingData() {
        if let path = book.manuscriptPath,
           let data = FileManager.default.contents(atPath: path),
           let text = String(data: data, encoding: .utf8) {
            manuscriptText = text
        }

        if let path = book.coverImagePath,
           let data = FileManager.default.contents(atPath: path),
           let uiImage = UIImage(data: data) {
            coverImage = uiImage
        }
    }

    private func handleManuscriptImport(_ result: Result<[URL], Error>) {
        guard let urls = try? result.get(),
              let url = urls.first else { return }

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        if let data = FileManager.default.contents(atPath: url.path),
           let text = String(data: data, encoding: .utf8) {
            manuscriptText = text
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let manuscriptURL = docs.appendingPathComponent("\(book.slug).md")
            try? data.write(to: manuscriptURL)
            book.manuscriptPath = manuscriptURL.path
            book.wordCount = text.split(separator: " ").count
        }
    }

    private func saveDraft() {
        book.isLocalDraft = true
        modelContext.insert(book)
        try? modelContext.save()
    }

    private func slugify(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func correctText(_ text: String) -> String {
        guard let settings = allSettings.first else { return text }
        let corrector = TextCorrector(rules: settings.autocorrectRules)
        return corrector.correct(text)
    }
}
