import Foundation

struct ServiceStatus {
    let connected: Bool
    let detail: String
    let error: String?
}

struct ConnectionReport {
    var github: ServiceStatus = .init(connected: false, detail: "Not checked", error: nil)
    var shopify: ServiceStatus = .init(connected: false, detail: "Not checked", error: nil)
    var tryPost: ServiceStatus = .init(connected: false, detail: "Not checked", error: nil)
    var checkedAt: Date = Date()
}

class ConnectionChecker {
    func checkAll(settings: AppSettings) async -> ConnectionReport {
        async let gh = checkGitHub(settings: settings)
        async let sh = checkShopify(settings: settings)
        async let tp = checkTryPost(settings: settings)
        let results = await (gh, sh, tp)
        return ConnectionReport(
            github: results.0,
            shopify: results.1,
            tryPost: results.2,
            checkedAt: Date()
        )
    }

    private func checkGitHub(settings: AppSettings) async -> ServiceStatus {
        guard !settings.githubPAT.isEmpty else {
            return ServiceStatus(connected: false, detail: "No PAT configured", error: "Add your GitHub Personal Access Token in Settings.")
        }
        let path = "/repos/\(settings.githubOwner)/\(settings.githubRepo)/contents/dove-harper-site/content/books"
        let url = URL(string: "https://api.github.com\(path)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(settings.githubPAT)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return ServiceStatus(connected: false, detail: "Invalid response", error: "Network error.")
            }
            if http.statusCode == 200 {
                if let items = try? JSONDecoder().decode([GitHubContent].self, from: data) {
                    let books = items.filter { $0.name.hasSuffix(".json") && !$0.name.hasPrefix("_") }
                    return ServiceStatus(connected: true, detail: "\(books.count) book\(books.count == 1 ? "" : "s") found", error: nil)
                }
                return ServiceStatus(connected: true, detail: "Connected", error: nil)
            } else if http.statusCode == 401 {
                return ServiceStatus(connected: false, detail: "HTTP 401", error: "Invalid GitHub PAT. Go to Settings and update your token.")
            } else if http.statusCode == 404 {
                return ServiceStatus(connected: false, detail: "HTTP 404", error: "Repo \(settings.githubOwner)/\(settings.githubRepo) not found. Check owner/repo in Settings.")
            } else {
                let body = String(data: data, encoding: .utf8) ?? ""
                return ServiceStatus(connected: false, detail: "HTTP \(http.statusCode)", error: "GitHub API error \(http.statusCode): \(body.prefix(100))")
            }
        } catch {
            return ServiceStatus(connected: false, detail: "Network error", error: error.localizedDescription)
        }
    }

    private func checkShopify(settings: AppSettings) async -> ServiceStatus {
        guard !settings.shopifyAccessToken.isEmpty else {
            return ServiceStatus(connected: false, detail: "No access token", error: "Add your Shopify Store Access Token in Settings.")
        }
        let url = URL(string: "https://\(settings.shopifyShopURL)/admin/api/2026-07/shop.json")!
        var request = URLRequest(url: url)
        request.setValue(settings.shopifyAccessToken, forHTTPHeaderField: "X-Shopify-Access-Token")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return ServiceStatus(connected: false, detail: "Invalid response", error: "Network error.")
            }
            if http.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let shop = json["shop"] as? [String: Any],
                   let name = shop["name"] as? String {
                    return ServiceStatus(connected: true, detail: name, error: nil)
                }
                return ServiceStatus(connected: true, detail: "Connected", error: nil)
            } else if http.statusCode == 401 || http.statusCode == 403 {
                return ServiceStatus(connected: false, detail: "HTTP \(http.statusCode)", error: "Invalid Shopify access token. Go to Settings and update your token.")
            } else {
                let body = String(data: data, encoding: .utf8) ?? ""
                return ServiceStatus(connected: false, detail: "HTTP \(http.statusCode)", error: "Shopify API error \(http.statusCode): \(body.prefix(100))")
            }
        } catch {
            return ServiceStatus(connected: false, detail: "Network error", error: error.localizedDescription)
        }
    }

    private func checkTryPost(settings: AppSettings) async -> ServiceStatus {
        guard !settings.tryPostAPIKey.isEmpty else {
            return ServiceStatus(connected: false, detail: "Not configured", error: "TryPost API key not set.")
        }
        let url = URL(string: "http://100.101.187.102:8000/api/social-accounts")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(settings.tryPostAPIKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return ServiceStatus(connected: false, detail: "Invalid response", error: "Network error.")
            }
            if http.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let accounts = json["accounts"] as? [[String: Any]] {
                    let names = accounts.compactMap { $0["platform"] as? String }
                    return ServiceStatus(connected: true, detail: "\(names.count) account\(names.count == 1 ? "" : "s") (\(names.joined(separator: ", ")))", error: nil)
                }
                return ServiceStatus(connected: true, detail: "Connected", error: nil)
            } else if http.statusCode == 401 || http.statusCode == 403 {
                return ServiceStatus(connected: false, detail: "HTTP \(http.statusCode)", error: "Invalid TryPost API key.")
            } else {
                let body = String(data: data, encoding: .utf8) ?? ""
                return ServiceStatus(connected: false, detail: "HTTP \(http.statusCode)", error: "TryPost API error \(http.statusCode): \(body.prefix(100))")
            }
        } catch {
            return ServiceStatus(connected: false, detail: "Offline or unreachable", error: "TryPost server at 100.101.187.102:8000 is not reachable.")
        }
    }
}
