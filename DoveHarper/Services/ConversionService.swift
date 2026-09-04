import Foundation

class ConversionService {
    private let githubService = GitHubService()

    func triggerAndMonitorConversion(
        owner: String,
        repo: String,
        slug: String,
        pat: String,
        onStatus: @escaping (PublishStatus) -> Void
    ) async throws -> String {
        onStatus(.waitingForActions)

        var lastRunID: Int?

        for attempt in 0..<12 {
            if let runs = try? await githubService.getLatestWorkflowRun(
                owner: owner, repo: repo, pat: pat
            ) {
                if let lastID = lastRunID, runs.id == lastID {
                    if runs.status == "completed" {
                        if runs.conclusion == "success" {
                            onStatus(.deploying)
                            try await Task.sleep(nanoseconds: 30_000_000_000)
                            let url = "https://doveharperauthor.com/books/\(slug)/"
                            onStatus(.done(url))
                            return url
                        } else {
                            let logs = try? await githubService.getWorkflowRunLog(
                                owner: owner, repo: repo, runID: runs.id, pat: pat
                            )
                            throw ConversionError.workflowFailed(logs ?? "Unknown error")
                        }
                    } else {
                        onStatus(.generatingEPUB)
                    }
                } else {
                    lastRunID = runs.id
                    onStatus(.generatingEPUB)
                }
            }

            try await Task.sleep(nanoseconds: 10_000_000_000)
            _ = attempt
        }

        throw ConversionError.timeout
    }

    func findConversionRun(
        owner: String,
        repo: String,
        afterSHA: String,
        pat: String
    ) async throws -> GitHubWorkflowRun? {
        let path = "/repos/\(owner)/\(repo)/actions/runs?head_sha=\(afterSHA)&per_page=5"
        guard let url = URL(string: "https://api.github.com\(path)") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        let runs = try? JSONDecoder().decode(GitHubWorkflowRuns.self, from: data)
        return runs?.workflow_runs.first
    }
}

enum ConversionError: LocalizedError {
    case workflowFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .workflowFailed(let logs): return "GitHub Actions failed:\n\(logs)"
        case .timeout: return "Conversion timed out"
        }
    }
}
