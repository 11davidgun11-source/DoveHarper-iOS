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
    private let log: (String) -> Void
    private let timeout: TimeInterval = 30

    init(log: @escaping (String) -> Void = { _ in }) {
        self.log = log
    }

    func checkAll(settings: AppSettings) async -> ConnectionReport {
        log("Checking GitHub...")
        async let gh = checkGitHub(settings: settings)
        log("Checking Shopify...")
        async let sh = checkShopify(settings: settings)
        log("Checking TryPost...")
        async let tp = checkTryPost(settings: settings)
        let results = await (gh, sh, tp)
        log("System check complete.")
        return ConnectionReport(
            github: results.0,
            shopify: results.1,
            tryPost: results.2,
            checkedAt: Date()
        )
    }

    private func checkGitHub(settings: AppSettings) async -> ServiceStatus {
        guard !settings.githubPAT.isEmpty else {
            log("GitHub: FAIL — no PAT configured")
            return ServiceStatus(connected: false, detail: "No PAT configured", error: "Add your GitHub Personal Access Token in Settings.")
        }

        log("GitHub: PAT present (\(settings.githubPAT.prefix(8))...)")
        log("GitHub: GET /repos/\(settings.githubOwner)/\(settings.githubRepo)/contents/...")

        let path = "/repos/\(settings.githubOwner)/\(settings.githubRepo)/contents/dove-harper-site/content/books"
        let url = URL(string: "https://api.github.com\(path)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(settings.githubPAT)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = timeout

        do {
            log("GitHub: Connecting to api.github.com...")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                log("GitHub: FAIL — invalid response")
                return ServiceStatus(connected: false, detail: "Invalid response", error: "Network error.")
            }

            log("GitHub: HTTP \(http.statusCode)")

            if http.statusCode == 200 {
                if let items = try? JSONDecoder().decode([GitHubContent].self, from: data) {
                    let books = items.filter { $0.name.hasSuffix(".json") && !$0.name.hasPrefix("_") }
                    let names = books.map { $0.name.replacingOccurrences(of: ".json", with: "") }
                    log("GitHub: OK — \(books.count) book\(books.count == 1 ? "" : "s"): \(names.joined(separator: ", "))")
                    return ServiceStatus(connected: true, detail: "\(books.count) book\(books.count == 1 ? "" : "s") found", error: nil)
                }
                log("GitHub: OK — connected (could not parse book list)")
                return ServiceStatus(connected: true, detail: "Connected", error: nil)
            } else if http.statusCode == 401 {
                log("GitHub: FAIL — 401 Unauthorized (bad PAT)")
                return ServiceStatus(connected: false, detail: "HTTP 401", error: "Invalid GitHub PAT. Go to Settings and update your token.")
            } else if http.statusCode == 404 {
                log("GitHub: FAIL — 404 Not Found (\(settings.githubOwner)/\(settings.githubRepo))")
                return ServiceStatus(connected: false, detail: "HTTP 404", error: "Repo \(settings.githubOwner)/\(settings.githubRepo) not found. Check owner/repo in Settings.")
            } else {
                let body = String(data: data, encoding: .utf8) ?? ""
                log("GitHub: FAIL — HTTP \(http.statusCode): \(body.prefix(60))")
                return ServiceStatus(connected: false, detail: "HTTP \(http.statusCode)", error: "GitHub API error \(http.statusCode): \(body.prefix(100))")
            }
        } catch let error as URLError where error.code == .timedOut {
            log("GitHub: FAIL — request timed out (30s)")
            return ServiceStatus(connected: false, detail: "Timeout", error: "GitHub API timed out after \(Int(timeout))s. Check your network connection.")
        } catch {
            log("GitHub: FAIL — \(error.localizedDescription)")
            return ServiceStatus(connected: false, detail: "Network error", error: error.localizedDescription)
        }
    }

    private func checkShopify(settings: AppSettings) async -> ServiceStatus {
        guard !settings.shopifyAccessToken.isEmpty else {
            log("Shopify: FAIL — no access token")
            return ServiceStatus(connected: false, detail: "No access token", error: "Add your Shopify Store Access Token in Settings.")
        }

        log("Shopify: Token present (\(settings.shopifyAccessToken.prefix(8))...)")
        log("Shopify: GET https://\(settings.shopifyShopURL)/admin/api/2026-07/shop.json")

        let url = URL(string: "https://\(settings.shopifyShopURL)/admin/api/2026-07/shop.json")!
        var request = URLRequest(url: url)
        request.setValue(settings.shopifyAccessToken, forHTTPHeaderField: "X-Shopify-Access-Token")
        request.timeoutInterval = timeout

        do {
            log("Shopify: Connecting to \(settings.shopifyShopURL)...")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                log("Shopify: FAIL — invalid response")
                return ServiceStatus(connected: false, detail: "Invalid response", error: "Network error.")
            }

            log("Shopify: HTTP \(http.statusCode)")

            if http.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let shop = json["shop"] as? [String: Any],
                   let name = shop["name"] as? String {
                    log("Shopify: OK — \(name)")
                    return ServiceStatus(connected: true, detail: name, error: nil)
                }
                log("Shopify: OK — connected")
                return ServiceStatus(connected: true, detail: "Connected", error: nil)
            } else if http.statusCode == 401 || http.statusCode == 403 {
                log("Shopify: FAIL — HTTP \(http.statusCode) (bad token)")
                return ServiceStatus(connected: false, detail: "HTTP \(http.statusCode)", error: "Invalid Shopify access token. Go to Settings and update your token.")
            } else {
                let body = String(data: data, encoding: .utf8) ?? ""
                log("Shopify: FAIL — HTTP \(http.statusCode): \(body.prefix(60))")
                return ServiceStatus(connected: false, detail: "HTTP \(http.statusCode)", error: "Shopify API error \(http.statusCode): \(body.prefix(100))")
            }
        } catch let error as URLError where error.code == .timedOut {
            log("Shopify: FAIL — request timed out (30s)")
            return ServiceStatus(connected: false, detail: "Timeout", error: "Shopify API timed out after \(Int(timeout))s. Check your network connection.")
        } catch {
            log("Shopify: FAIL — \(error.localizedDescription)")
            return ServiceStatus(connected: false, detail: "Network error", error: error.localizedDescription)
        }
    }

    private func checkTryPost(settings: AppSettings) async -> ServiceStatus {
        guard !settings.tryPostAPIKey.isEmpty else {
            log("TryPost: FAIL — not configured")
            return ServiceStatus(connected: false, detail: "Not configured", error: "TryPost API key not set.")
        }

        log("TryPost: Key present (\(settings.tryPostAPIKey.prefix(20))...)")
        log("TryPost: GET http://100.101.187.102:8000/api/social-accounts")

        let url = URL(string: "http://100.101.187.102:8000/api/social-accounts")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(settings.tryPostAPIKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout

        do {
            log("TryPost: Connecting to 100.101.187.102:8000...")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                log("TryPost: FAIL — invalid response")
                return ServiceStatus(connected: false, detail: "Invalid response", error: "Network error.")
            }

            log("TryPost: HTTP \(http.statusCode)")

            if http.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let accounts = json["accounts"] as? [[String: Any]] {
                    let names = accounts.compactMap { $0["platform"] as? String }
                    log("TryPost: OK — \(names.count) account\(names.count == 1 ? "" : "s"): \(names.joined(separator: ", "))")
                    return ServiceStatus(connected: true, detail: "\(names.count) account\(names.count == 1 ? "" : "s") (\(names.joined(separator: ", ")))", error: nil)
                }
                log("TryPost: OK — connected")
                return ServiceStatus(connected: true, detail: "Connected", error: nil)
            } else if http.statusCode == 401 || http.statusCode == 403 {
                log("TryPost: FAIL — HTTP \(http.statusCode) (bad key)")
                return ServiceStatus(connected: false, detail: "HTTP \(http.statusCode)", error: "Invalid TryPost API key.")
            } else {
                let body = String(data: data, encoding: .utf8) ?? ""
                log("TryPost: FAIL — HTTP \(http.statusCode): \(body.prefix(60))")
                return ServiceStatus(connected: false, detail: "HTTP \(http.statusCode)", error: "TryPost API error \(http.statusCode): \(body.prefix(100))")
            }
        } catch let error as URLError where error.code == .timedOut {
            log("TryPost: FAIL — request timed out (30s)")
            return ServiceStatus(connected: false, detail: "Timeout", error: "TryPost timed out after \(Int(timeout))s. Server may be offline.")
        } catch {
            log("TryPost: FAIL — \(error.localizedDescription)")
            return ServiceStatus(connected: false, detail: "Offline or unreachable", error: "TryPost server at 100.101.187.102:8000 is not reachable.")
        }
    }
}
