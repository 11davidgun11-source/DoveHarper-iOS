import Foundation

class GitHubService {
    private let baseURL = "https://api.github.com"

    func makeRequest(
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

    // MARK: - Fetch Book List

    func listBooks(owner: String, repo: String, pat: String) async throws -> [BookJSON] {
        let path = "/repos/\(owner)/\(repo)/contents/dove-harper-site/content/books"
        let (data, response) = try await makeRequest(path: path, pat: pat)

        guard response.statusCode == 200 else {
            throw GitHubError.apiError("Failed to list books: \(response.statusCode)")
        }

        let contents = try JSONDecoder().decode([GitHubContent].self, from: data)
        let jsonFiles = contents.filter { $0.name.hasSuffix(".json") && !$0.name.hasPrefix("_") }

        if jsonFiles.isEmpty {
            throw GitHubError.apiError("No .json book files found in dove-harper-site/content/books/")
        }

        var books: [BookJSON] = []
        var errors: [String] = []

        for file in jsonFiles {
            do {
                let book = try await getBook(owner: owner, repo: repo, slug: file.name.replacingOccurrences(of: ".json", with: ""), pat: pat)
                books.append(book)
            } catch {
                errors.append("\(file.name): \(error.localizedDescription)")
            }
        }

        if books.isEmpty && !errors.isEmpty {
            throw GitHubError.apiError("Failed to load any books:\n" + errors.joined(separator: "\n"))
        }

        return books
    }

    // MARK: - Fetch Single Book

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

    // MARK: - Fetch File Content (manuscript, cover, etc.)

    func getFileContent(
        owner: String,
        repo: String,
        path: String,
        pat: String
    ) async throws -> Data {
        let urlPath = "/repos/\(owner)/\(repo)/contents/\(path)"
        let (data, response) = try await makeRequest(path: urlPath, pat: pat)
        guard response.statusCode == 200 else {
            throw GitHubError.apiError("File not found: \(path) (\(response.statusCode))")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GitHubError.apiError("Invalid JSON response for \(path)")
        }

        let sha = json["sha"] as? String

        // Method 1: base64 content field
        if let encoded = json["content"] as? String, !encoded.isEmpty,
           let decoded = Data(base64Encoded: encoded) {
            return decoded
        }

        // Method 2: download_url
        if let downloadURLString = json["download_url"] as? String,
           let downloadURL = URL(string: downloadURLString) {
            let (dlData, dlResp) = try await URLSession.shared.data(from: downloadURL)
            if let httpResp = dlResp as? HTTPURLResponse, httpResp.statusCode == 200 {
                return dlData
            }
        }

        // Method 3: git blob API
        if let sha = sha {
            let blobPath = "/repos/\(owner)/\(repo)/git/blobs/\(sha)"
            let (blobData, blobResp) = try await makeRequest(path: blobPath, pat: pat)
            if blobResp.statusCode == 200,
               let blobJson = try? JSONSerialization.jsonObject(with: blobData) as? [String: Any],
               let blobContent = blobJson["content"] as? String,
               let decoded = Data(base64Encoded: blobContent) {
                return decoded
            }
        }

        throw GitHubError.apiError("Could not fetch file content: \(path)")
    }

    func getFileAsString(
        owner: String,
        repo: String,
        path: String,
        pat: String
    ) async throws -> String {
        let data = try await getFileContent(owner: owner, repo: repo, path: path, pat: pat)
        guard let text = String(data: data, encoding: .utf8) else {
            throw GitHubError.encodingError
        }
        return text
    }

    // MARK: - Delete File (for deleting books)

    func deleteFile(
        owner: String,
        repo: String,
        path: String,
        message: String,
        pat: String
    ) async throws {
        // Get current SHA via Contents API
        let urlPath = "/repos/\(owner)/\(repo)/contents/\(path)"
        let (data, response) = try await makeRequest(path: urlPath, pat: pat)
        guard response.statusCode == 200 else { return }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sha = json["sha"] as? String else { return }

        struct DeleteBody: Codable {
            let message: String
            let sha: String
            let branch: String
        }

        let body = DeleteBody(message: message, sha: sha, branch: "main")
        let bodyData = try JSONEncoder().encode(body)
        let (_, delResp) = try await makeRequest(path: urlPath, method: "DELETE", body: bodyData, pat: pat)

        guard delResp.statusCode == 200 else {
            throw GitHubError.apiError("Failed to delete \(path): \(delResp.statusCode)")
        }
    }

    // MARK: - Workflow Monitoring

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
