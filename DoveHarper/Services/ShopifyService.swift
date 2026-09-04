import Foundation

class ShopifyService {
    func createProduct(
        shopURL: String,
        accessToken: String,
        title: String,
        descriptionHTML: String,
        handle: String,
        tags: [String],
        price: String,
        coverBase64: String?,
        coverFilename: String?
    ) async throws -> ShopifyProductData {
        let url = URL(string: "https://\(shopURL)/admin/api/2026-07/graphql.json")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(accessToken, forHTTPHeaderField: "X-Shopify-Access-Token")

        let tagsString = tags.joined(separator: ", ")

        let mutation = """
        {
            "query": "mutation productCreate($input: ProductInput!) { productCreate(input: $input) { product { id title handle status } userErrors { field message } } }",
            "variables": {
                "input": {
                    "title": \(title.jsonEncoded),
                    "descriptionHtml": \(descriptionHTML.jsonEncoded),
                    "vendor": "Dove Harper",
                    "productType": "Books > Romance",
                    "status": "ACTIVE",
                    "handle": \(handle.jsonEncoded),
                    "tags": \(tagsString.jsonEncoded),
                    "seo": {
                        "title": \(title.jsonEncoded),
                        "description": \(title.jsonEncoded)
                    }
                }
            }
        }
        """

        request.httpBody = mutation.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown"
            throw ShopifyError.apiError("Product creation failed: \(body)")
        }

        let result = try JSONDecoder().decode(ShopifyGraphQLResponse.self, from: data)

        if let errors = result.errors, !errors.isEmpty {
            throw ShopifyError.apiError(errors.map(\.message).joined(separator: ", "))
        }

        guard let productCreate = result.data?.productCreate,
              let product = productCreate.product else {
            let userErrors = result.data?.productCreate?.userErrors ?? []
            throw ShopifyError.apiError(userErrors.map(\.message).joined(separator: ", "))
        }

        if !userErrorsContainsErrors(result.data?.productCreate?.userErrors) {
            return product
        }

        throw ShopifyError.apiError("Unknown error creating product")
    }

    private func userErrorsContainsErrors(_ errors: [ShopifyUserError]?) -> Bool {
        guard let errors = errors else { return false }
        return errors.contains { !$0.message.isEmpty }
    }

    func setPrice(
        shopURL: String,
        accessToken: String,
        productID: Int64,
        variantID: Int64,
        price: String
    ) async throws {
        let cleanPrice = price.replacingOccurrences(of: "$", with: "")
        let url = URL(string: "https://\(shopURL)/admin/api/2026-07/products/\(productID)/variants/\(variantID).json")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(accessToken, forHTTPHeaderField: "X-Shopify-Access-Token")

        let body: [String: Any] = [
            "variant": [
                "id": variantID,
                "price": cleanPrice,
                "requires_shipping": false,
                "inventory_policy": "continue"
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ShopifyError.apiError("Failed to set price")
        }
    }

    func uploadCover(
        shopURL: String,
        accessToken: String,
        productID: Int64,
        coverBase64: String,
        filename: String
    ) async throws {
        let url = URL(string: "https://\(shopURL)/admin/api/2026-07/products/\(productID)/images.json")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(accessToken, forHTTPHeaderField: "X-Shopify-Access-Token")

        let body: [String: Any] = [
            "image": [
                "attachment": coverBase64,
                "filename": filename
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ShopifyError.apiError("Failed to upload cover")
        }
    }

    func publishToStorefront(
        shopURL: String,
        accessToken: String,
        productID: Int64
    ) async throws {
        let url = URL(string: "https://\(shopURL)/admin/api/2026-07/products/\(productID).json")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(accessToken, forHTTPHeaderField: "X-Shopify-Access-Token")

        let formatter = ISO8601DateFormatter()
        let now = formatter.string(from: Date())

        let body: [String: Any] = [
            "product": [
                "id": productID,
                "published": true,
                "published_at": now
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ShopifyError.apiError("Failed to publish to storefront")
        }
    }
}

enum ShopifyError: LocalizedError {
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .apiError(let msg): return msg
        }
    }
}

extension String {
    var jsonEncoded: String {
        guard let data = try? JSONEncoder().encode(self),
              let str = String(data: data, encoding: .utf8) else {
            return "\"\(self)\""
        }
        return str
    }
}
