import SwiftUI
import SwiftData

struct BookDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var book: BookEntity
    @State private var showingEdit = false
    @State private var showingDeleteConfirmation = false
    @State private var deleteConfirmationText = ""
    @State private var isDeleting = false
    @State private var showingPriceEdit = false
    @State private var newPrice = ""
    @State private var newCheckoutURL = ""
    @State private var showingCheckoutEdit = false
    @State private var saved = false

    @Query private var allSettings: [AppSettings]

    var body: some View {
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
                    Text("No product URL set. Create the product in Shopify, then paste the URL here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(book.primaryCheckoutURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Button {
                    newCheckoutURL = book.primaryCheckoutURL
                    showingCheckoutEdit = true
                } label: {
                    Label(book.primaryCheckoutURL.isEmpty ? "Paste Product URL" : "Update Product URL", systemImage: "doc.on.clipboard")
                }
            }

            Section("Info") {
                LabeledContent("Title", value: book.title)
                LabeledContent("Slug", value: book.slug)
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
                    Spacer()
                    Button("Edit") {
                        newPrice = book.priceLabel
                        showingPriceEdit = true
                    }
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
                Button {
                    showingEdit = true
                } label: {
                    Label("Edit Book", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Book", systemImage: "trash")
                }
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showingEdit) {
            NavigationStack {
                BookEditorView(book: book)
                    .navigationTitle("Edit \(book.title)")
                    .navigationBarTitleDisplayMode(.inline)
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
        .alert("Edit Price", isPresented: $showingPriceEdit) {
            TextField("Price (e.g. $4.99)", text: $newPrice)
            Button("Save") {
                book.priceLabel = newPrice
                Task { await updateBook() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Shopify Product URL", isPresented: $showingCheckoutEdit) {
            TextField("https://doveharpershop.myshopify.com/products/...", text: $newCheckoutURL)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Button("Save") {
                book.primaryCheckoutURL = newCheckoutURL
                Task { await updateBook() }
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                withAnimation { saved = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { saved = false }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Paste the Shopify product URL after creating the product.")
        }
    }

    private func deleteBook() async {
        guard let settings = allSettings.first else { return }
        guard !settings.githubPAT.isEmpty else { return }

        isDeleting = true
        defer { isDeleting = false }

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

    private func updateBook() async {
        guard let settings = allSettings.first else { return }
        guard !settings.githubPAT.isEmpty else { return }

        let github = GitHubService()
        let bookJSON = book.toBookJSON()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let jsonData = try? encoder.encode(bookJSON) else { return }

        do {
            try await github.pushFile(
                owner: settings.githubOwner,
                repo: settings.githubRepo,
                path: "dove-harper-site/content/books/\(book.slug).json",
                content: jsonData,
                message: "Update \(book.title)",
                pat: settings.githubPAT
            )
            try modelContext.save()
        } catch {
            print("Update failed: \(error)")
        }
    }
}
