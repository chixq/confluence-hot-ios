import Foundation

final class ConfluenceClient {
    private let configuration: ServerConfiguration
    private let password: String
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(configuration: ServerConfiguration, password: String, session: URLSession = .shared) {
        self.configuration = configuration
        self.password = password
        self.session = session
    }

    var baseURL: URL {
        configuration.baseURL
    }

    func validateSession() async throws -> UserProfile {
        try await request("/rest/api/user/current")
    }

    func fetchRecentlyUpdated(start: Int = 0, limit: Int = 30) async throws -> [ContentItem] {
        let response: ContentSearchResponse = try await request(
            "/rest/api/content/search",
            queryItems: [
                URLQueryItem(name: "cql", value: "type in (page,blogpost) order by lastmodified desc"),
                URLQueryItem(name: "start", value: String(start)),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "expand", value: "space,history.lastUpdated")
            ]
        )
        return response.results.map { $0.item(origin: .recent) }
    }

    func fetchPopular(start: Int = 0, limit: Int = 30) async throws -> [ContentItem] {
        do {
            let response: PopularStreamResponse = try await request(
                "/rest/popular/1/stream/content",
                queryItems: [
                    URLQueryItem(name: "start", value: String(start)),
                    URLQueryItem(name: "limit", value: String(limit))
                ]
            )
            let items = response.streamItems.map { $0.item() }
            if !items.isEmpty {
                return items
            }
        } catch ConfluenceClientError.unauthorized {
            throw ConfluenceClientError.unauthorized
        } catch {
            // Some Server/Data Center installations disable the popular stream plugin.
        }

        return try await fetchRecentlyUpdated(start: start, limit: limit)
    }

    func fetchSpaces(start: Int = 0, limit: Int = 50) async throws -> [ConfluenceSpace] {
        let response: SpaceResponse = try await request(
            "/rest/api/space",
            queryItems: [
                URLQueryItem(name: "start", value: String(start)),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "type", value: "global")
            ]
        )
        return response.results
    }

    func fetchSpaceContent(spaceKey: String, start: Int = 0, limit: Int = 30) async throws -> [ContentItem] {
        let escapedKey = Self.escapeCQL(spaceKey)
        let response: ContentSearchResponse = try await request(
            "/rest/api/content/search",
            queryItems: [
                URLQueryItem(name: "cql", value: "space = \"\(escapedKey)\" and type in (page,blogpost) order by lastmodified desc"),
                URLQueryItem(name: "start", value: String(start)),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "expand", value: "space,history.lastUpdated")
            ]
        )
        return response.results.map { $0.item(origin: .search) }
    }

    func search(_ query: String, limit: Int = 30) async throws -> [ContentItem] {
        try await searchContent(contentQuery: query, authorQuery: "", start: 0, limit: limit)
    }

    func searchContent(contentQuery: String, authorQuery: String, start: Int = 0, limit: Int = 30) async throws -> [ContentItem] {
        let cleaned = contentQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedAuthor = authorQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty || !cleanedAuthor.isEmpty else {
            return try await fetchRecentlyUpdated(start: start, limit: limit)
        }

        var filters = ["type in (page,blogpost)"]
        if !cleaned.isEmpty {
            let escaped = Self.escapeCQL(cleaned)
            filters.append("(title ~ \"\(escaped)\" or text ~ \"\(escaped)\")")
        }
        if !cleanedAuthor.isEmpty {
            let escapedAuthor = Self.escapeCQL(cleanedAuthor)
            filters.append("(creator = \"\(escapedAuthor)\" or contributor = \"\(escapedAuthor)\")")
        }

        let cql = "\(filters.joined(separator: " and ")) order by lastmodified desc"
        let response: ContentSearchResponse = try await request(
            "/rest/api/content/search",
            queryItems: [
                URLQueryItem(name: "cql", value: cql),
                URLQueryItem(name: "start", value: String(start)),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "expand", value: "space,history.lastUpdated,body.view")
            ]
        )
        return response.results.map { $0.item(origin: .search) }
    }

    func fetchDetail(id: String) async throws -> ContentDetail {
        try await request(
            "/rest/api/content/\(id)",
            queryItems: [
                URLQueryItem(name: "expand", value: "body.view,space,version")
            ]
        )
    }

    func fetchComments(contentID: String, limit: Int = 50) async throws -> [CommentItem] {
        let response: CommentResponse = try await request(
            "/rest/api/content/\(contentID)/child/comment",
            queryItems: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "expand", value: "body.view,history.createdBy,version")
            ]
        )
        return response.results.map { $0.item() }
    }

    func postComment(contentID: String, containerType: String, text: String) async throws -> CommentItem {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw ConfluenceClientError.emptyComment
        }

        let requestBody = CreateCommentRequest(
            type: "comment",
            container: ContentContainer(id: contentID, type: containerType.lowercased().contains("blog") ? "blogpost" : "page"),
            body: StorageBody(storage: StorageRepresentation(value: Self.storageHTML(from: cleaned), representation: "storage"))
        )

        let result: CommentResult = try await request(
            "/rest/api/content",
            method: "POST",
            queryItems: [URLQueryItem(name: "expand", value: "body.view,history.createdBy,version")],
            body: requestBody
        )
        return result.item()
    }

    func fetchAdminSystemInfo() async throws -> AdminSystemInfo {
        let systemJSON: JSONValue = try await request("/rest/api/settings/systemInfo")
        let systemInfo = Self.flattenSystemInfo(systemJSON)

        async let users = fetchUserCount()
        async let pages = fetchContentCount(cql: "type = page")
        async let blogs = fetchContentCount(cql: "type = blogpost")
        async let logins = fetchAuditCount(searchString: "login")

        return AdminSystemInfo(
            generatedAt: Date(),
            userCount: await users,
            pageCount: await pages,
            blogPostCount: await blogs,
            loginAuditCount: await logins,
            rawSystemInfo: systemInfo
        )
    }

    private func request<T: Decodable, Body: Encodable>(
        _ path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: Body? = nil
    ) async throws -> T {
        let url = try makeURL(path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ConfluenceHot-iOS", forHTTPHeaderField: "User-Agent")
        request.setValue(basicAuthHeader(), forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConfluenceClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw ConfluenceClientError.decoding(error.localizedDescription)
            }
        case 401, 403:
            throw ConfluenceClientError.unauthorized
        default:
            let message = String(data: data, encoding: .utf8)
            throw ConfluenceClientError.httpStatus(httpResponse.statusCode, message)
        }
    }

    private func request<T: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        try await request(path, method: "GET", queryItems: queryItems, body: Optional<EmptyBody>.none)
    }

    private func fetchUserCount() async -> Int? {
        do {
            let response: SearchUserResponse = try await request(
                "/rest/api/search/user",
                queryItems: [
                    URLQueryItem(name: "cql", value: "user.fullname ~ \"\""),
                    URLQueryItem(name: "limit", value: "1")
                ]
            )
            return response.totalSize ?? response.size
        } catch {
            return nil
        }
    }

    private func fetchContentCount(cql: String) async -> Int? {
        do {
            let response: ContentSearchResponse = try await request(
                "/rest/api/content/search",
                queryItems: [
                    URLQueryItem(name: "cql", value: cql),
                    URLQueryItem(name: "limit", value: "1")
                ]
            )
            return response.totalSize
        } catch {
            return nil
        }
    }

    private func fetchAuditCount(searchString: String) async -> Int? {
        do {
            let response: GenericCountResponse = try await request(
                "/rest/api/audit",
                queryItems: [
                    URLQueryItem(name: "searchString", value: searchString),
                    URLQueryItem(name: "limit", value: "1")
                ]
            )
            return response.totalSize ?? response.totalCount
        } catch {
            return nil
        }
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) else {
            throw ConfluenceClientError.invalidBaseURL
        }

        let basePath = components.percentEncodedPath.trimmedTrailingSlashes()
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        components.percentEncodedPath = "\(basePath)\(normalizedPath)"
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw ConfluenceClientError.invalidBaseURL
        }
        return url
    }

    private func basicAuthHeader() -> String {
        let rawToken = "\(configuration.username):\(password)"
        let encoded = Data(rawToken.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    private static func escapeCQL(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func flattenSystemInfo(_ value: JSONValue) -> [String: String] {
        guard case .object(let object) = value else { return [:] }
        var output: [String: String] = [:]
        for (key, value) in object {
            switch value {
            case .object(let nested):
                for (nestedKey, nestedValue) in nested {
                    let description = nestedValue.description
                    if !description.isEmpty {
                        output["\(key).\(nestedKey)"] = description
                    }
                }
            default:
                let description = value.description
                if !description.isEmpty {
                    output[key] = description
                }
            }
        }
        return output
    }

    private static func storageHTML(from text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")

        let paragraphs = escaped
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { "<p>\($0)</p>" }

        return paragraphs.isEmpty ? "<p></p>" : paragraphs.joined()
    }
}

private struct EmptyBody: Encodable {}

private struct CreateCommentRequest: Encodable {
    let type: String
    let container: ContentContainer
    let body: StorageBody
}

private struct ContentContainer: Encodable {
    let id: String
    let type: String
}

private struct StorageBody: Encodable {
    let storage: StorageRepresentation
}

private struct StorageRepresentation: Encodable {
    let value: String
    let representation: String
}

enum ConfluenceClientError: LocalizedError, Equatable {
    case invalidBaseURL
    case missingUsername
    case missingPassword
    case invalidResponse
    case unauthorized
    case httpStatus(Int, String?)
    case decoding(String)
    case keychain(String)
    case emptyComment

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "站点 URL 无效"
        case .missingUsername:
            return "请输入用户名"
        case .missingPassword:
            return "请输入密码"
        case .invalidResponse:
            return "服务器响应无效"
        case .unauthorized:
            return "用户名或密码不正确，或当前账号没有权限"
        case .httpStatus(let status, _):
            return "请求失败，状态码 \(status)"
        case .decoding:
            return "响应格式无法解析"
        case .keychain(let message):
            return message
        case .emptyComment:
            return "请输入回复内容"
        }
    }
}

private extension String {
    func trimmedTrailingSlashes() -> String {
        var value = self
        while value.count > 1 && value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}
