import Foundation
import SwiftData

@Model
final class BookEntity {
    var slug: String
    var title: String
    var author: String
    var series: String
    var seriesOrder: String
    var isNovella: Bool
    var releaseDate: String
    var wordCount: Int
    var isLatestRelease: Bool
    var tropes: [String]
    var themes: [String]
    var forFansOf: [String]
    var contentNotes: [String]
    var tickerQuotes: [String]
    var shortDescription: String
    var descriptionText: String
    var priceLabel: String
    var isFree: Bool
    var status: String
    var primaryCheckoutURL: String
    var checkoutProviderLabel: String
    var coverImagePath: String?
    var manuscriptPath: String?
    var isLocalDraft: Bool
    var lastPublishedDate: Date?
    var liveURL: String?

    init(slug: String = "", title: String = "", author: String = "Dove Harper") {
        self.slug = slug
        self.title = title
        self.author = author
        self.series = "Standalone"
        self.seriesOrder = ""
        self.isNovella = false
        self.releaseDate = ""
        self.wordCount = 0
        self.isLatestRelease = true
        self.tropes = []
        self.themes = []
        self.forFansOf = []
        self.contentNotes = []
        self.tickerQuotes = []
        self.shortDescription = ""
        self.descriptionText = ""
        self.priceLabel = ""
        self.isFree = false
        self.status = "draft"
        self.primaryCheckoutURL = ""
        self.checkoutProviderLabel = "Shopify"
        self.coverImagePath = nil
        self.manuscriptPath = nil
        self.isLocalDraft = true
        self.lastPublishedDate = nil
        self.liveURL = nil
    }

    func toBookJSON() -> BookJSON {
        BookJSON(
            slug: slug,
            title: title,
            author: author,
            catalogStatus: "published",
            seriesType: seriesOrder.isEmpty ? "standalone" : "series",
            series: series,
            seriesOrder: seriesOrder.isEmpty ? nil : seriesOrder,
            isNovella: isNovella,
            isBundle: false,
            bundleMembers: [],
            releaseDate: releaseDate,
            wordCount: wordCount,
            isLatestRelease: isLatestRelease,
            tropes: tropes,
            themes: themes,
            forFansOf: forFansOf,
            tickerQuotes: tickerQuotes,
            formats: ["EPUB", "PDF", "DOCX"],
            isFree: isFree,
            primaryCheckoutURL: primaryCheckoutURL,
            backupCheckoutURL: "",
            checkoutProviderLabel: checkoutProviderLabel,
            backupCheckoutProviderLabel: "Backup",
            priceLabel: priceLabel,
            formatsIncluded: isFree ? "EPUB + PDF + DOCX" : "EPUB + PDF + DOCX",
            sampleEPUBURL: "/samples/\(slug)/dove-harper-\(slug)-epub-sample.epub",
            samplePDFURL: "/samples/\(slug)/dove-harper-\(slug)-pdf-sample.pdf",
            sampleDOCXURL: "/samples/\(slug)/dove-harper-\(slug)-docx-sample.docx",
            coverImage: "/assets/img/covers/\(slug)-cover.jpg",
            shortDescription: shortDescription,
            description: descriptionText,
            contentNotes: contentNotes.joined(separator: ", "),
            status: status,
            sourceMarkdown: "manuscripts/\(slug).md"
        )
    }
}

@Model
final class QueueEntry {
    var bookSlug: String
    var bookTitle: String
    var scheduledDate: Date
    var status: String
    var manuscriptData: Data?
    var coverData: Data?
    var bookJSONString: String?
    var createdAt: Date

    init(bookSlug: String, bookTitle: String, scheduledDate: Date) {
        self.bookSlug = bookSlug
        self.bookTitle = bookTitle
        self.scheduledDate = scheduledDate
        self.status = "pending"
        self.manuscriptData = nil
        self.coverData = nil
        self.bookJSONString = nil
        self.createdAt = Date()
    }
}

@Model
final class AppSettings {
    var githubPAT: String
    var githubOwner: String
    var githubRepo: String
    var shopifyShopURL: String
    var shopifyAccessToken: String
    var defaultAuthor: String
    var timezone: String
    var autocorrectRules: [String: String]

    init() {
        self.githubPAT = ""
        self.githubOwner = "doveharperauthor"
        self.githubRepo = "DoveHarper-site"
        self.shopifyShopURL = "doveharpershop.myshopify.com"
        self.shopifyAccessToken = ""
        self.defaultAuthor = "Dove Harper"
        self.timezone = "Europe/Lisbon"
        self.autocorrectRules = [
            "explicit content": "Explicit Content",
            "nsfw": "NSFW",
            "mature content": "Mature Content"
        ]
    }
}

struct BookJSON: Codable {
    let slug: String
    let title: String
    let author: String
    let catalogStatus: String
    let seriesType: String
    let series: String
    let seriesOrder: String?
    let isNovella: Bool
    let isBundle: Bool
    let bundleMembers: [String]
    let releaseDate: String
    let wordCount: Int
    let isLatestRelease: Bool
    let tropes: [String]
    let themes: [String]
    let forFansOf: [String]
    let tickerQuotes: [String]
    let formats: [String]
    let isFree: Bool
    let primaryCheckoutURL: String
    let backupCheckoutURL: String
    let checkoutProviderLabel: String
    let backupCheckoutProviderLabel: String
    let priceLabel: String
    let formatsIncluded: String
    let sampleEPUBURL: String
    let samplePDFURL: String
    let sampleDOCXURL: String
    let coverImage: String
    let shortDescription: String
    let description: String
    let contentNotes: String
    let status: String
    let sourceMarkdown: String

    enum CodingKeys: String, CodingKey {
        case slug, title, author, series, tropes, themes, forFansOf, formats, status
        case catalogStatus = "catalog_status"
        case seriesType = "series_type"
        case seriesOrder = "series_order"
        case isNovella = "is_novella"
        case isBundle = "is_bundle"
        case bundleMembers = "bundle_members"
        case releaseDate = "release_date"
        case wordCount = "word_count"
        case isLatestRelease = "is_latest_release"
        case tickerQuotes = "ticker_quotes"
        case isFree = "is_free"
        case primaryCheckoutURL = "primary_checkout_url"
        case backupCheckoutURL = "backup_checkout_url"
        case checkoutProviderLabel = "checkout_provider_label"
        case backupCheckoutProviderLabel = "backup_checkout_provider_label"
        case priceLabel = "price_label"
        case formatsIncluded = "formats_included"
        case sampleEPUBURL = "sample_epub_url"
        case samplePDFURL = "sample_pdf_url"
        case sampleDOCXURL = "sample_docx_url"
        case coverImage = "cover_image"
        case shortDescription = "short_description"
        case description
        case contentNotes = "content_notes"
        case sourceMarkdown = "source_markdown"
    }

    func toJSONString() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct GitHubContent: Codable {
    let name: String
    let path: String
    let sha: String
    let size: Int
    let downloadURL: String?
    let content: String?
    let encoding: String?
}

struct GitHubFileUpdate: Codable {
    let message: String
    let content: String
    let sha: String?
    let branch: String
}

struct GitHubTreeItem: Codable {
    let path: String
    let mode: String
    let type: String
    let sha: String
    let size: Int?
    let url: String?
}

struct GitHubTree: Codable {
    let sha: String
    let url: String
    let tree: [GitHubTreeItem]
    let truncated: Bool?
}

struct GitHubCommit: Codable {
    let sha: String
    let commit: CommitInfo
    let htmlURL: String
}

struct CommitInfo: Codable {
    let message: String
}

struct GitHubWorkflowRun: Codable {
    let id: Int
    let status: String
    let conclusion: String?
    let name: String
    let createdAt: String
    let updatedAt: String
    let runNumber: Int
    let htmlURL: String
    let headBranch: String
    let headSHA: String
}

struct GitHubWorkflowRuns: Codable {
    let total_count: Int
    let workflow_runs: [GitHubWorkflowRun]
}

struct ShopifyProduct: Codable {
    let product: ShopifyProductData
}

struct ShopifyProductData: Codable {
    let id: Int64
    let title: String
    let handle: String
    let status: String
    let variants: [ShopifyVariant]?
}

struct ShopifyVariant: Codable {
    let id: Int64
    let price: String
}

struct ShopifyGraphQLResponse: Codable {
    let data: ShopifyGraphQLData?
    let errors: [ShopifyGraphQLError]?
}

struct ShopifyGraphQLData: Codable {
    let productCreate: ShopifyProductCreate?
}

struct ShopifyProductCreate: Codable {
    let product: ShopifyProductData?
    let userErrors: [ShopifyUserError]
}

struct ShopifyGraphQLError: Codable {
    let message: String
}

struct ShopifyUserError: Codable {
    let field: [String]?
    let message: String
}

enum PublishStatus {
    case idle
    case pushingManuscript
    case pushingCover
    case pushingBookJSON
    case waitingForActions
    case generatingEPUB
    case generatingPDF
    case deploying
    case done(String)
    case failed(String)

    var displayText: String {
        switch self {
        case .idle: return "Ready"
        case .pushingManuscript: return "Uploading manuscript..."
        case .pushingCover: return "Uploading cover..."
        case .pushingBookJSON: return "Pushing book metadata..."
        case .waitingForActions: return "Waiting for GitHub Actions..."
        case .generatingEPUB: return "Generating EPUB sample..."
        case .generatingPDF: return "Generating PDF sample..."
        case .deploying: return "Deploying to site..."
        case .done(let url): return "Published! \(url)"
        case .failed(let error): return "Failed: \(error)"
        }
    }

    var progress: Double {
        switch self {
        case .idle: return 0
        case .pushingManuscript: return 0.15
        case .pushingCover: return 0.3
        case .pushingBookJSON: return 0.45
        case .waitingForActions: return 0.5
        case .generatingEPUB: return 0.65
        case .generatingPDF: return 0.8
        case .deploying: return 0.9
        case .done: return 1.0
        case .failed: return 0
        }
    }
}
