import Foundation

class GitHubService {
    private let baseURL = "https://api.github.com"

    private func makeRequest(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        pat: String
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw GitHubError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        if let body = body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse
        }

        return (data, httpResponse)
    }

    func listBooks(owner: String, repo: String, pat: String) async throws -> [BookJSON] {
        let path = "/repos/\(owner)/\(repo)/contents/dove-harper-site/content/books"
        let (data, response) = try await makeRequest(path: path, pat: pat)

        guard response.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown"
            print("[GitHubService] listBooks failed: \(response.statusCode) - \(body.prefix(200))")
            throw GitHubError.apiError("Failed to list books: \(response.statusCode)")
        }

        let contents = try JSONDecoder().decode([GitHubContent].self, from: data)
        var books: [BookJSON] = []
        var errors: [String] = []

        let jsonFiles = contents.filter { $0.name.hasSuffix(".json") && !$0.name.hasPrefix("_") }
        print("[GitHubService] Found \(jsonFiles.count) book files")

        if jsonFiles.isEmpty {
            throw GitHubError.apiError("No .json book files found in dove-harper-site/content/books/")
        }

        for file in jsonFiles {
            let bookPath = "/repos/\(owner)/\(repo)/contents/dove-harper-site/content/books/\(file.name)"
            do {
                let (bookData, bookResp) = try await makeRequest(path: bookPath, pat: pat)
                guard bookResp.statusCode == 200 else {
                    errors.append("\(file.name): HTTP \(bookResp.statusCode)")
                    continue
                }
                let fileContent = try JSONDecoder().decode(GitHubContent.self, from: bookData)
                if let encoded = fileContent.content,
                   let decoded = Data(base64Encoded: encoded) {
                    do {
                        let book = try JSONDecoder().decode(BookJSON.self, from: decoded)
                        books.append(book)
                        print("[GitHubService] Loaded: \(book.title) [\(book.status)]")
                    } catch {
                        let msg = "\(file.name): \(error.localizedDescription)"
                        errors.append(msg)
                        print("[GitHubService] DECODE FAILED: \(msg)")
                    }
                } else {
                    let blobPath = "/repos/\(owner)/\(repo)/git/blobs/\(fileContent.sha)"
                    let (blobData, blobResp) = try await makeRequest(path: blobPath, pat: pat)
                    if blobResp.statusCode == 200,
                       let blob = try? JSONDecoder().decode(GitHubBlob.self, from: blobData),
                       let decoded = Data(base64Encoded: blob.content) {
                        do {
                            let book = try JSONDecoder().decode(BookJSON.self, from: decoded)
                            books.append(book)
                            print("[GitHubService] Loaded via blob: \(book.title) [\(book.status)]")
                        } catch {
                            errors.append("\(file.name) (blob): \(error.localizedDescription)")
                        }
                    } else {
                        errors.append("\(file.name): no content and blob fetch failed")
                    }
                }
            } catch {
                errors.append("\(file.name): \(error.localizedDescription)")
            }
        }

        if books.isEmpty && !errors.isEmpty {
            throw GitHubError.apiError("Decode failed for all books:\n" + errors.joined(separator: "\n"))
        }

        return books
    }

    func getBook(owner: String, repo: String, slug: String, pat: String) async throws -> BookJSON {
        let path = "/repos/\(owner)/\(repo)/contents/dove-harper-site/content/books/\(slug).json"
        let (data, response) = try await makeRequest(path: path, pat: pat)

        guard response.statusCode == 200 else {
            throw GitHubError.apiError("Failed to get book: \(response.statusCode)")
        }

        let content = try JSONDecoder().decode(GitHubContent.self, from: data)
        guard let downloadURL = content.downloadURL,
              let url = URL(string: downloadURL) else {
            throw GitHubError.invalidURL
        }

        let (bookData, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(BookJSON.self, from: bookData)
    }

    func getBookSHA(owner: String, repo: String, path: String, pat: String) async throws -> String? {
        let urlPath = "/repos/\(owner)/\(repo)/contents/\(path)"
        let (data, response) = try await makeRequest(path: urlPath, pat: pat)

        if response.statusCode == 200 {
            let content = try JSONDecoder().decode(GitHubContent.self, from: data)
            return content.sha
        }
        return nil
    }

    func pushFile(
        owner: String,
        repo: String,
        path: String,
        content: Data,
        message: String,
        pat: String
    ) async throws -> String {
        let base64Content = content.base64EncodedString()
        let sha = try? await getBookSHA(owner: owner, repo: repo, path: path, pat: pat)

        var update = GitHubFileUpdate(
            message: message,
            content: base64Content,
            sha: sha,
            branch: "main"
        )

        let encoder = JSONEncoder()
        let body = try encoder.encode(update)
        let urlPath = "/repos/\(owner)/\(repo)/contents/\(path)"
        let (data, response) = try await makeRequest(path: urlPath, method: "PUT", body: body, pat: pat)

        guard response.statusCode == 200 || response.statusCode == 201 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GitHubError.apiError("Failed to push \(path): \(response.statusCode) - \(errorBody)")
        }

        let result = try JSONDecoder().decode(GitHubContent.self, from: data)
        return result.sha
    }

    func pushString(
        owner: String,
        repo: String,
        path: String,
        content: String,
        message: String,
        pat: String
    ) async throws -> String {
        guard let data = content.data(using: .utf8) else {
            throw GitHubError.encodingError
        }
        return try await pushFile(owner: owner, repo: repo, path: path, content: data, message: message, pat: pat)
    }

    func deleteFile(
        owner: String,
        repo: String,
        path: String,
        message: String,
        pat: String
    ) async throws {
        let sha = try await getBookSHA(owner: owner, repo: repo, path: path, pat: pat)
        guard let sha = sha else { return }

        struct DeleteUpdate: Codable {
            let message: String
            let sha: String
            let branch: String
        }

        let update = DeleteUpdate(message: message, sha: sha, branch: "main")
        let body = try JSONEncoder().encode(update)
        let urlPath = "/repos/\(owner)/\(repo)/contents/\(path)"
        let (_, response) = try await makeRequest(path: urlPath, method: "DELETE", body: body, pat: pat)

        guard response.statusCode == 200 else {
            throw GitHubError.apiError("Failed to delete \(path): \(response.statusCode)")
        }
    }

    func getLatestWorkflowRun(owner: String, repo: String, pat: String) async throws -> GitHubWorkflowRun? {
        let path = "/repos/\(owner)/\(repo)/actions/runs?per_page=5&status=in_progress"
        let (data, response) = try await makeRequest(path: path, pat: pat)

        guard response.statusCode == 200 else { return nil }
        let runs = try JSONDecoder().decode(GitHubWorkflowRuns.self, from: data)
        return runs.workflow_runs.first
    }

    func waitForWorkflowCompletion(
        owner: String,
        repo: String,
        runID: Int,
        pat: String,
        onStatus: @escaping (String) -> Void
    ) async throws -> GitHubWorkflowRun {
        var attempts = 0
        let maxAttempts = 60

        while attempts < maxAttempts {
            let path = "/repos/\(owner)/\(repo)/actions/runs/\(runID)"
            let (data, response) = try await makeRequest(path: path, pat: pat)

            guard response.statusCode == 200 else {
                throw GitHubError.apiError("Failed to check workflow status")
            }

            let run = try JSONDecoder().decode(GitHubWorkflowRun.self, from: data)

            if run.status == "completed" {
                return run
            }

            onStatus(run.status)
            try await Task.sleep(nanoseconds: 5_000_000_000)
            attempts += 1
        }

        throw GitHubError.timeout
    }

    func getWorkflowRunLog(
        owner: String,
        repo: String,
        runID: Int,
        pat: String
    ) async throws -> String {
        let path = "/repos/\(owner)/\(repo)/actions/runs/\(runID)/logs"
        let (data, response) = try await makeRequest(path: path, pat: pat)

        guard response.statusCode == 200 else {
            return "Could not fetch logs: \(response.statusCode)"
        }

        return String(data: data, encoding: .utf8) ?? "No log data"
    }
}

enum GitHubError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(String)
    case encodingError
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid response from GitHub"
        case .apiError(let msg): return msg
        case .encodingError: return "Failed to encode content"
        case .timeout: return "Workflow timed out waiting for completion"
        }
    }
}
