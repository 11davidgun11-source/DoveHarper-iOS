import Foundation
import UIKit

/// Manages local book files in Documents/books/{slug}/
/// Drafts = local files. Live books = always fetched fresh from GitHub.
class BookFileManager {
    private let booksDir: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        booksDir = docs.appendingPathComponent("books")
        try? FileManager.default.createDirectory(at: booksDir, withIntermediateDirectories: true)
    }

    // MARK: - Local Draft Operations

    func draftDir(for slug: String) -> URL {
        booksDir.appendingPathComponent(slug)
    }

    func draftJSONPath(for slug: String) -> URL {
        draftDir(for: slug).appendingPathComponent("book.json")
    }

    func draftManuscriptPath(for slug: String) -> URL {
        draftDir(for: slug).appendingPathComponent("manuscript.md")
    }

    func draftCoverPath(for slug: String) -> URL {
        draftDir(for: slug).appendingPathComponent("cover.jpg")
    }

    func hasDraft(slug: String) -> Bool {
        FileManager.default.fileExists(atPath: draftJSONPath(for: slug).path)
    }

    func loadDraft(slug: String) -> BookJSON? {
        let path = draftJSONPath(for: slug)
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? JSONDecoder().decode(BookJSON.self, from: data)
    }

    func loadDraftManuscript(slug: String) -> String? {
        let path = draftManuscriptPath(for: slug)
        guard let data = try? Data(contentsOf: path) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func loadDraftCover(slug: String) -> UIImage? {
        let path = draftCoverPath(for: slug)
        guard let data = try? Data(contentsOf: path) else { return nil }
        return UIImage(data: data)
    }

    func listDraftSlugs() -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: booksDir, includingPropertiesForKeys: nil) else {
            return []
        }
        return contents
            .filter { $0.hasDirectoryPath }
            .map { $0.lastPathComponent }
            .filter { hasDraft(slug: $0) }
    }

    func saveDraft(book: BookJSON, manuscript: String? = nil, coverData: Data? = nil) throws {
        let dir = draftDir(for: book.slug)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Save book JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(book)
        try jsonData.write(to: draftJSONPath(for: book.slug))

        // Save manuscript if provided
        if let manuscript = manuscript, let data = manuscript.data(using: .utf8) {
            try data.write(to: draftManuscriptPath(for: book.slug))
        }

        // Save cover if provided
        if let coverData = coverData {
            try coverData.write(to: draftCoverPath(for: book.slug))
        }
    }

    func saveDraftManuscript(slug: String, text: String) throws {
        let dir = draftDir(for: slug)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = text.data(using: .utf8) else { return }
        try data.write(to: draftManuscriptPath(for: slug))
    }

    func saveDraftCover(slug: String, jpegData: Data) throws {
        let dir = draftDir(for: slug)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try jpegData.write(to: draftCoverPath(for: slug))
    }

    func deleteDraft(slug: String) throws {
        let dir = draftDir(for: slug)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    // MARK: - Helper: Load live book from GitHub data

    func loadLiveBook(from json: BookJSON) -> BookEntity {
        let book = BookEntity(
            slug: json.slug,
            title: json.title,
            author: json.author
        )
        book.series = json.series
        book.seriesOrder = json.seriesOrder ?? ""
        book.isNovella = json.isNovella
        book.releaseDate = json.releaseDate
        book.wordCount = json.wordCount
        book.isLatestRelease = json.isLatestRelease
        book.tropes = json.tropes
        book.themes = json.themes
        book.forFansOf = json.forFansOf
        book.contentNotes = json.contentNotes.isEmpty ? [] : json.contentNotes.components(separatedBy: ", ")
        book.tickerQuotes = json.tickerQuotes
        book.shortDescription = json.shortDescription
        book.descriptionText = json.description
        book.priceLabel = json.priceLabel
        book.isFree = json.isFree
        book.status = json.status
        book.primaryCheckoutURL = json.primaryCheckoutURL
        book.checkoutProviderLabel = json.checkoutProviderLabel
        book.isLocalDraft = false
        return book
    }

    /// Clear all local books (used on fresh sync)
    func clearAllLocalBooks() {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: booksDir, includingPropertiesForKeys: nil) else {
            return
        }
        for url in contents {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
