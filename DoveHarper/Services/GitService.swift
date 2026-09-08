import Foundation

/// Git Data API service for atomic commits via GitHub.
/// Creates proper git commits: blob → tree → commit → ref update.
class GitService {
    private let baseURL = "https://api.github.com"

    // MARK: - Git Data API

    /// Get the current commit SHA for a branch
    func getHeadCommit(owner: String, repo: String, branch: String, pat: String) async throws -> (commitSHA: String, treeSHA: String) {
        let path = "/repos/\(owner)/\(repo)/git/refs/heads/\(branch)"
        let (data, response) = try await makeRequest(path: path, pat: pat)

        guard response.statusCode == 200 else {
            throw GitError.apiError("Failed to get ref: \(response.statusCode)")
        }

        let refRaw = String(data: data, encoding: .utf8) ?? "nil"
        print("[GitService] Ref response: \(refRaw.prefix(300))")
        let ref = try JSONDecoder().decode(GitRef.self, from: data)
        let commitSHA = ref.object.sha

        // Get the commit to find the tree SHA
        let commitPath = "/repos/\(owner)/\(repo)/git/commits/\(commitSHA)"
        let (commitData, commitResp) = try await makeRequest(path: commitPath, pat: pat)
        guard commitResp.statusCode == 200 else {
            throw GitError.apiError("Failed to get commit: \(commitResp.statusCode)")
        }

        let commitRaw = String(data: commitData, encoding: .utf8) ?? "nil"
        print("[GitService] Commit response: \(commitRaw.prefix(500))")
        let commit = try JSONDecoder().decode(GitCommit.self, from: commitData)
        return (commitSHA, commit.tree.sha)
    }

    /// Create a blob from content
    func createBlob(owner: String, repo: String, content: Data, encoding: String = "base64", pat: String) async throws -> String {
        struct BlobRequest: Codable {
            let content: String
            let encoding: String
        }

        let body = BlobRequest(
            content: content.base64EncodedString(),
            encoding: encoding
        )

        let path = "/repos/\(owner)/\(repo)/git/blobs"
        let bodyData = try JSONEncoder().encode(body)
        let (data, response) = try await makeRequest(path: path, method: "POST", body: bodyData, pat: pat)

        guard response.statusCode == 201 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown"
            throw GitError.apiError("Failed to create blob: \(response.statusCode) - \(errorBody)")
        }

        let blobRaw = String(data: data, encoding: .utf8) ?? "nil"
        print("[GitService] Blob response: \(blobRaw.prefix(300))")
        let blob = try JSONDecoder().decode(GitBlob.self, from: data)
        return blob.sha
    }

    /// Create a tree from base tree + updated blobs
    func createTree(owner: String, repo: String, baseTreeSHA: String, files: [(path: String, blobSHA: String, mode: String)], pat: String) async throws -> String {
        struct TreeEntry: Codable {
            let path: String
            let mode: String
            let type: String
            let sha: String
        }

        struct TreeRequest: Codable {
            let base_tree: String
            let tree: [TreeEntry]
        }

        let entries = files.map { file in
            TreeEntry(
                path: file.path,
                mode: file.mode,
                type: "blob",
                sha: file.blobSHA
            )
        }

        let body = TreeRequest(base_tree: baseTreeSHA, tree: entries)
        let path = "/repos/\(owner)/\(repo)/git/trees"
        let bodyData = try JSONEncoder().encode(body)
        let (data, response) = try await makeRequest(path: path, method: "POST", body: bodyData, pat: pat)

        guard response.statusCode == 201 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown"
            throw GitError.apiError("Failed to create tree: \(response.statusCode) - \(errorBody)")
        }

        print("[GitService] Tree response: \(String(data: data, encoding: .utf8) ?? "nil")")
        let decoder = JSONDecoder()
        let tree = try decoder.decode(GitTree.self, from: data)
        print("[GitService] Tree decoded: sha=\(tree.sha.prefix(8)), entries=\(tree.tree.count)")
        return tree.sha
    }

    /// Create a commit
    func createCommit(owner: String, repo: String, message: String, treeSHA: String, parentSHA: String, pat: String) async throws -> String {
        struct CommitRequest: Codable {
            let message: String
            let tree: String
            let parents: [String]
        }

        let body = CommitRequest(message: message, tree: treeSHA, parents: [parentSHA])
        let path = "/repos/\(owner)/\(repo)/git/commits"
        let bodyData = try JSONEncoder().encode(body)
        let (data, response) = try await makeRequest(path: path, method: "POST", body: bodyData, pat: pat)

        guard response.statusCode == 201 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown"
            throw GitError.apiError("Failed to create commit: \(response.statusCode) - \(errorBody)")
        }

        let commit = try JSONDecoder().decode(GitCommit.self, from: data)
        return commit.sha
    }

    /// Update a branch ref to point to a new commit
    func updateRef(owner: String, repo: String, branch: String, commitSHA: String, pat: String) async throws {
        struct RefUpdate: Codable {
            let sha: String
            let force: Bool
        }

        let body = RefUpdate(sha: commitSHA, force: false)
        let path = "/repos/\(owner)/\(repo)/git/refs/heads/\(branch)"
        let bodyData = try JSONEncoder().encode(body)
        let (_, response) = try await makeRequest(path: path, method: "PATCH", body: bodyData, pat: pat)

        guard response.statusCode == 200 else {
            throw GitError.apiError("Failed to update ref: \(response.statusCode)")
        }
    }

    // MARK: - High-Level Commit

    /// Create an atomic commit with multiple file changes
    func commitChanges(
        owner: String,
        repo: String,
        branch: String,
        message: String,
        files: [(path: String, data: Data)],
        pat: String
    ) async throws -> String {
        print("[GitService] Starting atomic commit: \(files.count) files")

        // Step 1: Get current HEAD
        let (commitSHA, treeSHA) = try await getHeadCommit(owner: owner, repo: repo, branch: branch, pat: pat)
        print("[GitService] HEAD: \(commitSHA.prefix(8)), tree: \(treeSHA.prefix(8))")

        // Step 2: Create blobs for all files
        var fileEntries: [(path: String, blobSHA: String, mode: String)] = []
        for file in files {
            let blobSHA = try await createBlob(owner: owner, repo: repo, content: file.data, pat: pat)
            fileEntries.append((path: file.path, blobSHA: blobSHA, mode: "100644"))
            print("[GitService] Blob created: \(file.path) -> \(blobSHA.prefix(8))")
        }

        // Step 3: Create tree
        let newTreeSHA = try await createTree(owner: owner, repo: repo, baseTreeSHA: treeSHA, files: fileEntries, pat: pat)
        print("[GitService] Tree: \(newTreeSHA.prefix(8))")

        // Step 4: Create commit
        let newCommitSHA = try await createCommit(owner: owner, repo: repo, message: message, treeSHA: newTreeSHA, parentSHA: commitSHA, pat: pat)
        print("[GitService] Commit: \(newCommitSHA.prefix(8))")

        // Step 5: Update ref
        try await updateRef(owner: owner, repo: repo, branch: branch, commitSHA: newCommitSHA, pat: pat)
        print("[GitService] Ref updated to \(newCommitSHA.prefix(8))")

        return newCommitSHA
    }

    // MARK: - REST API Helper

    private func makeRequest(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        pat: String
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw GitError.invalidURL
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
            throw GitError.invalidResponse
        }

        return (data, httpResponse)
    }
}

// MARK: - Git API Models

struct GitRef: Codable {
    let ref: String
    let object: GitObject

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ref = (try? c.decode(String.self, forKey: .ref)) ?? ""
        object = (try? c.decode(GitObject.self, forKey: .object)) ?? GitObject(sha: "", type: "", url: "")
    }
}

struct GitObject: Codable {
    let sha: String
    let type: String
    let url: String

    init(sha: String, type: String, url: String) {
        self.sha = sha
        self.type = type
        self.url = url
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sha = (try? c.decode(String.self, forKey: .sha)) ?? ""
        type = (try? c.decode(String.self, forKey: .type)) ?? ""
        url = (try? c.decode(String.self, forKey: .url)) ?? ""
    }
}

struct GitCommit: Codable {
    let sha: String
    let message: String
    let tree: GitObject
    let parents: [GitObject]?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sha = (try? c.decode(String.self, forKey: .sha)) ?? ""
        message = (try? c.decode(String.self, forKey: .message)) ?? ""
        tree = (try? c.decode(GitObject.self, forKey: .tree)) ?? GitObject(sha: "", type: "", url: "")
        parents = try? c.decode([GitObject].self, forKey: .parents)
    }
}

struct GitBlob: Codable {
    let sha: String
    let size: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sha = (try? c.decode(String.self, forKey: .sha)) ?? ""
        size = (try? c.decode(Int.self, forKey: .size)) ?? 0
    }
}

struct GitTree: Codable {
    let sha: String
    let tree: [GitTreeEntry]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sha = (try? c.decode(String.self, forKey: .sha)) ?? ""
        tree = (try? c.decode([GitTreeEntry].self, forKey: .tree)) ?? []
    }
}

struct GitTreeEntry: Codable {
    let path: String
    let mode: String
    let type: String?
    let sha: String
    let size: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? c.decode(String.self, forKey: .path)) ?? ""
        mode = (try? c.decode(String.self, forKey: .mode)) ?? "100644"
        type = try? c.decode(String.self, forKey: .type)
        sha = (try? c.decode(String.self, forKey: .sha)) ?? ""
        size = try? c.decode(Int.self, forKey: .size)
    }
}

// MARK: - Errors

enum GitError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid response"
        case .apiError(let msg): return msg
        }
    }
}
