import SwiftUI
import SwiftData

struct PublishView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var book: BookEntity
    var coverImage: UIImage?
    var manuscriptText: String

    @State private var status: PublishStatus = .idle
    @State private var progress: Double = 0
    @State private var statusText = "Preparing..."
    @State private var liveURL: String?
    @State private var showingResult = false
    @State private var errorDetail: String?

    @Query private var allSettings: [AppSettings]
    private var settings: AppSettings? { allSettings.first }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: statusIcon)
                    .font(.system(size: 64))
                    .foregroundStyle(statusColor)
                    .padding(.bottom, 16)

                Text(statusText)
                    .font(.title3)
                    .multilineTextAlignment(.center)

                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 32)

                if case .failed(let detail) = status {
                    ScrollView {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding()
                    }
                    .frame(maxHeight: 200)
                    .background(.red.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal, 32)
                }

                if case .done(let url) = status {
                    VStack(spacing: 12) {
                        Button("Open Live Page") {
                            UIApplication.shared.open(URL(string: url)!)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Copy URL") {
                            UIPasteboard.general.string = url
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Spacer()

                if case .failed = status {
                    Button("Retry") {
                        Task { await publish() }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 8)
                }

                Button("Close") {
                    dismiss()
                }
                .padding(.bottom, 16)
            }
            .navigationTitle("Publishing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if case .idle = status {
                        Button("Publish") {
                            Task { await publish() }
                        }
                        .disabled(book.slug.isEmpty || book.title.isEmpty)
                    }
                }
            }
        }
        .interactiveDismissDisabled(status is PublishingState)
    }

    private var statusIcon: String {
        switch status {
        case .idle: return "arrow.up.circle"
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        default: return "arrow.up.circle"
        }
    }

    private var statusColor: Color {
        switch status {
        case .idle: return .blue
        case .done: return .green
        case .failed: return .red
        default: return .orange
        }
    }

    private func publish() async {
        guard let settings = allSettings.first else {
            status = .failed("No settings configured. Go to Settings tab.")
            return
        }

        guard !settings.githubPAT.isEmpty else {
            status = .failed("GitHub PAT not configured. Go to Settings tab.")
            return
        }

        status = .pushingManuscript
        statusText = "Uploading manuscript..."
        progress = 0.1

        let github = GitHubService()

        do {
            if !manuscriptText.isEmpty {
                let manuscriptData = manuscriptText.data(using: .utf8)!
                try await github.pushFile(
                    owner: settings.githubOwner,
                    repo: settings.githubRepo,
                    path: "dove-harper-site/manuscripts/\(book.slug).md",
                    content: manuscriptData,
                    message: "Add manuscript for \(book.title)",
                    pat: settings.githubPAT
                )
            }

            status = .pushingCover
            statusText = "Uploading cover..."
            progress = 0.25

            if let cover = coverImage,
               let jpegData = cover.jpegData(compressionQuality: 0.9) {
                try await github.pushFile(
                    owner: settings.githubOwner,
                    repo: settings.githubRepo,
                    path: "dove-harper-site/public/assets/img/covers/\(book.slug)-cover.jpg",
                    content: jpegData,
                    message: "Add cover for \(book.title)",
                    pat: settings.githubPAT
                )
            }

            status = .pushingBookJSON
            statusText = "Pushing book metadata..."
            progress = 0.4

            book.status = "published"
            book.isLocalDraft = false
            book.lastPublishedDate = Date()
            book.liveURL = "https://doveharperauthor.com/books/\(book.slug)/"

            let bookJSON = book.toBookJSON()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(bookJSON)

            try await github.pushFile(
                owner: settings.githubOwner,
                repo: settings.githubRepo,
                path: "dove-harper-site/content/books/\(book.slug).json",
                content: jsonData,
                message: "Add \(book.title) to catalog",
                pat: settings.githubPAT
            )

            modelContext.insert(book)
            try modelContext.save()

            status = .waitingForActions
            statusText = "Waiting for GitHub Actions..."
            progress = 0.5

            let conversion = ConversionService()
            let finalURL = try await conversion.triggerAndMonitorConversion(
                owner: settings.githubOwner,
                repo: settings.githubRepo,
                slug: book.slug,
                pat: settings.githubPAT,
                onStatus: { newStatus in
                    DispatchQueue.main.async {
                        self.status = newStatus
                        self.progress = newStatus.progress
                        self.statusText = newStatus.displayText
                    }
                }
            )

            liveURL = finalURL
            status = .done(finalURL)
            statusText = "Published successfully!"
            progress = 1.0

        } catch {
            status = .failed(error.localizedDescription)
            statusText = "Publishing failed"
        }
    }
}

enum PublishingState {
    case publishing
}

extension PublishStatus {
    var isPublishing: Bool {
        switch self {
        case .pushingManuscript, .pushingCover, .pushingBookJSON,
             .waitingForActions, .generatingEPUB, .generatingPDF, .deploying:
            return true
        default:
            return false
        }
    }
}
