import Foundation

final class ConfluenceClient {
    private let configuration: ServerConfiguration
    private let password: String
    private let session: URLSession
    private let cacheStore: ConfluenceCacheStore
    private let decoder = JSONDecoder()

    init(configuration: ServerConfiguration, password: String, session: URLSession = .shared, cacheStore: ConfluenceCacheStore? = nil) {
        self.configuration = configuration
        self.password = password
        self.session = session
        self.cacheStore = cacheStore ?? ConfluenceCacheStore(configuration: configuration)
    }

    var baseURL: URL {
        configuration.baseURL
    }

    func validateSession() async throws -> UserProfile {
        try await request("/rest/api/user/current")
    }

    func fetchRecentlyUpdated(start: Int = 0, limit: Int = 30, cachePolicy: ConfluenceCachePolicy = .useCache) async throws -> [ContentItem] {
        let cacheKey = ConfluenceContentListCacheKey.recent(start: start, limit: limit)
        if cachePolicy.allowsFreshRead,
           let cached = await cacheStore.cachedContentList(for: cacheKey) {
            return cached
        }

        do {
            let response: ContentSearchResponse = try await request(
                "/rest/api/content/search",
                queryItems: [
                    URLQueryItem(name: "cql", value: "type in (page,blogpost) order by lastmodified desc"),
                    URLQueryItem(name: "start", value: String(start)),
                    URLQueryItem(name: "limit", value: String(limit)),
                    URLQueryItem(name: "expand", value: "space,history.lastUpdated")
                ]
            )
            let items = response.results.map { $0.item(origin: .recent) }
            await cacheStore.storeContentList(items, for: cacheKey)
            return items
        } catch {
            if cachePolicy.allowsStaleFallback,
               let cached = await cacheStore.cachedContentList(for: cacheKey, maxAge: nil) {
                return cached
            }
            throw error
        }
    }

    func fetchDrafts(limit: Int = 50) async throws -> [ContentItem] {
        let response: ContentSearchResponse = try await request(
            "/rest/api/content/search",
            queryItems: [
                URLQueryItem(name: "cql", value: "type in (page,blogpost) and status = draft order by lastmodified desc"),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "expand", value: "space,history.createdBy,history.lastUpdated")
            ]
        )
        return response.results.map { $0.item(origin: .recent) }
    }

    func fetchPopular(start: Int = 0, limit: Int = 30, cachePolicy: ConfluenceCachePolicy = .useCache) async throws -> [ContentItem] {
        let cacheKey = ConfluenceContentListCacheKey.popular(start: start, limit: limit)
        if cachePolicy.allowsFreshRead,
           let cached = await cacheStore.cachedContentList(for: cacheKey) {
            return cached
        }

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
                await cacheStore.storeContentList(items, for: cacheKey)
                return items
            }
        } catch ConfluenceClientError.unauthorized {
            throw ConfluenceClientError.unauthorized
        } catch {
            if cachePolicy.allowsStaleFallback,
               let cached = await cacheStore.cachedContentList(for: cacheKey, maxAge: nil) {
                return cached
            }
            // Some Server/Data Center installations disable the popular stream plugin.
        }

        return try await fetchRecentlyUpdated(start: start, limit: limit, cachePolicy: cachePolicy)
    }

    func fetchSpaces(start: Int = 0, limit: Int = 50, cachePolicy: ConfluenceCachePolicy = .useCache) async throws -> [ConfluenceSpace] {
        if cachePolicy.allowsFreshRead,
           let cached = await cacheStore.cachedSpaces(start: start, limit: limit) {
            return cached
        }

        do {
            let response: SpaceResponse = try await request(
                "/rest/api/space",
                queryItems: [
                    URLQueryItem(name: "start", value: String(start)),
                    URLQueryItem(name: "limit", value: String(limit)),
                    URLQueryItem(name: "type", value: "global")
                ]
            )
            await cacheStore.storeSpaces(response.results, start: start, limit: limit)
            return response.results
        } catch {
            if cachePolicy.allowsStaleFallback,
               let cached = await cacheStore.cachedSpaces(start: start, limit: limit, maxAge: nil) {
                return cached
            }
            throw error
        }
    }

    func fetchSpaceContent(spaceKey: String, start: Int = 0, limit: Int = 30, cachePolicy: ConfluenceCachePolicy = .useCache) async throws -> [ContentItem] {
        let cacheKey = ConfluenceContentListCacheKey.space(spaceKey: spaceKey, start: start, limit: limit)
        if cachePolicy.allowsFreshRead,
           let cached = await cacheStore.cachedContentList(for: cacheKey) {
            return cached
        }

        do {
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
            let items = response.results.map { $0.item(origin: .search) }
            await cacheStore.storeContentList(items, for: cacheKey)
            return items
        } catch {
            if cachePolicy.allowsStaleFallback,
               let cached = await cacheStore.cachedContentList(for: cacheKey, maxAge: nil) {
                return cached
            }
            throw error
        }
    }

    func fetchSpaceRootPages(spaceKey: String, start: Int = 0, limit: Int = 30) async throws -> [ContentItem] {
        let response: ContentSearchResponse = try await request(
            "/rest/api/space/\(spaceKey)/content/page",
            queryItems: [
                URLQueryItem(name: "depth", value: "root"),
                URLQueryItem(name: "start", value: String(start)),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "expand", value: "space,history.createdBy,history.lastUpdated")
            ]
        )
        return response.results.map { $0.item(origin: .search, prefersCreatedAuthor: true) }
    }

    func fetchChildPages(parentID: String, start: Int = 0, limit: Int = 30) async throws -> [ContentItem] {
        let response: ContentSearchResponse = try await request(
            "/rest/api/content/\(parentID)/child/page",
            queryItems: [
                URLQueryItem(name: "start", value: String(start)),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "expand", value: "space,history.createdBy,history.lastUpdated")
            ]
        )
        return response.results.map { $0.item(origin: .search, prefersCreatedAuthor: true) }
    }

    func search(_ query: String, limit: Int = 30, cachePolicy: ConfluenceCachePolicy = .useCache) async throws -> [ContentItem] {
        try await searchContent(contentQuery: query, authorQuery: "", start: 0, limit: limit, cachePolicy: cachePolicy)
    }

    func searchContent(contentQuery: String, authorQuery: String, start: Int = 0, limit: Int = 30, cachePolicy: ConfluenceCachePolicy = .useCache) async throws -> [ContentItem] {
        let cleaned = contentQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedAuthor = authorQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty || !cleanedAuthor.isEmpty else {
            return try await fetchRecentlyUpdated(start: start, limit: limit, cachePolicy: cachePolicy)
        }

        let cacheKey = ConfluenceContentListCacheKey.search(contentQuery: cleaned, authorQuery: cleanedAuthor, start: start, limit: limit)
        if cachePolicy.allowsFreshRead,
           let cached = await cacheStore.cachedContentList(for: cacheKey) {
            return cached
        }

        do {
            let items = try await searchContentFromNetwork(contentQuery: cleaned, authorQuery: cleanedAuthor, start: start, limit: limit)
            await cacheStore.storeContentList(items, for: cacheKey)
            return items
        } catch {
            if cachePolicy.allowsStaleFallback,
               let cached = await cacheStore.cachedContentList(for: cacheKey, maxAge: nil) {
                return cached
            }
            throw error
        }
    }

    private func searchContentFromNetwork(contentQuery: String, authorQuery: String, start: Int, limit: Int) async throws -> [ContentItem] {
        if !authorQuery.isEmpty {
            return try await searchContentWithAuthorFilter(contentQuery: contentQuery, authorQuery: authorQuery, start: start, limit: limit)
        }

        var filters = ["type in (page,blogpost)"]
        if !contentQuery.isEmpty {
            let escaped = Self.escapeCQL(contentQuery)
            filters.append("(title ~ \"\(escaped)\" or text ~ \"\(escaped)\")")
        }

        let cql = "\(filters.joined(separator: " and ")) order by lastmodified desc"
        return try await fetchSearchItems(cql: cql, start: start, limit: limit)
            .filter { Self.matchesContent($0, query: contentQuery) }
    }

    func fetchDetail(id: String, cachePolicy: ConfluenceCachePolicy = .useCache) async throws -> ContentDetail {
        if cachePolicy.allowsFreshRead,
           let cached = await cacheStore.cachedContentDetail(id: id) {
            return cached
        }

        do {
            let detail: ContentDetail = try await request(
                "/rest/api/content/\(id)",
                queryItems: [
                    URLQueryItem(name: "expand", value: "body.view,body.storage,space,version")
                ]
            )
            await cacheStore.storeContentDetail(detail)
            return detail
        } catch {
            if cachePolicy.allowsStaleFallback,
               let cached = await cacheStore.cachedContentDetail(id: id, maxAge: nil) {
                return cached
            }
            throw error
        }
    }

    func fetchComments(contentID: String, limit: Int = 50, cachePolicy: ConfluenceCachePolicy = .useCache) async throws -> [CommentItem] {
        if cachePolicy.allowsFreshRead,
           let cached = await cacheStore.cachedComments(contentID: contentID, limit: limit) {
            return cached
        }

        do {
            let response: CommentResponse = try await request(
                "/rest/api/content/\(contentID)/child/comment",
                queryItems: [
                    URLQueryItem(name: "limit", value: String(limit)),
                    URLQueryItem(name: "expand", value: "body.view,history.createdBy,version")
                ]
            )
            let comments = response.results.map { $0.item() }
            await cacheStore.storeComments(comments, contentID: contentID, limit: limit)
            return comments
        } catch {
            if cachePolicy.allowsStaleFallback,
               let cached = await cacheStore.cachedComments(contentID: contentID, limit: limit, maxAge: nil) {
                return cached
            }
            throw error
        }
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
        await cacheStore.invalidateComments(contentID: contentID)
        return result.item()
    }

    func updateContent(id: String, type: String, title: String, storageHTML: String, versionNumber: Int) async throws -> ContentDetail {
        let body = UpdateContentRequest(
            id: id,
            type: type,
            title: title,
            version: ContentVersionRequest(number: versionNumber),
            body: StorageBody(storage: StorageRepresentation(value: storageHTML, representation: "storage"))
        )
        let updated: ContentDetail = try await request(
            "/rest/api/content/\(id)",
            method: "PUT",
            queryItems: [URLQueryItem(name: "expand", value: "body.view,body.storage,space,version")],
            body: body
        )
        await cacheStore.storeContentDetail(updated)
        await cacheStore.invalidateContentLists(containingContentID: id)
        return updated
    }

    func copyContent(detail: ContentDetail) async throws -> ContentDetail {
        guard let storageHTML = detail.storageHTML else {
            throw ConfluenceClientError.missingStorageBody
        }
        guard let spaceKey = detail.space?.key else {
            throw ConfluenceClientError.missingSpace
        }
        let body = CreateContentRequest(
            type: detail.type,
            title: "\(detail.title) 副本",
            space: SpaceKeyRequest(key: spaceKey),
            body: StorageBody(storage: StorageRepresentation(value: storageHTML, representation: "storage"))
        )
        let copied: ContentDetail = try await request(
            "/rest/api/content",
            method: "POST",
            queryItems: [URLQueryItem(name: "expand", value: "body.view,body.storage,space,version")],
            body: body
        )
        await cacheStore.storeContentDetail(copied)
        return copied
    }

    func createPage(title: String, spaceKey: String, storageHTML: String) async throws -> ContentDetail {
        let body = CreateContentRequest(
            type: "page",
            title: title,
            space: SpaceKeyRequest(key: spaceKey),
            body: StorageBody(storage: StorageRepresentation(value: storageHTML, representation: "storage"))
        )
        let detail: ContentDetail = try await request(
            "/rest/api/content",
            method: "POST",
            queryItems: [URLQueryItem(name: "expand", value: "body.view,body.storage,space,version")],
            body: body
        )
        await cacheStore.storeContentDetail(detail)
        return detail
    }

    func deleteContent(id: String) async throws {
        try await requestVoid("/rest/api/content/\(id)", method: "DELETE")
        await cacheStore.removeContent(id: id)
    }

    func fetchData(url: URL, cachePolicy: ConfluenceCachePolicy = .useCache) async throws -> (data: Data, mimeType: String) {
        if cachePolicy.allowsFreshRead,
           let cached = await cacheStore.cachedData(for: url) {
            return cached
        }

        var request = URLRequest(url: url)
        request.setValue("ConfluenceHot-iOS", forHTTPHeaderField: "User-Agent")
        request.setValue(basicAuthHeader(), forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ConfluenceClientError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw ConfluenceClientError.httpStatus(httpResponse.statusCode, nil)
            }
            let mimeType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.components(separatedBy: ";").first ?? Self.mimeType(for: url)
            await cacheStore.storeData(data, mimeType: mimeType, for: url)
            return (data, mimeType)
        } catch {
            if cachePolicy.allowsStaleFallback,
               let cached = await cacheStore.cachedData(for: url, maxAge: nil) {
                return cached
            }
            throw error
        }
    }

    func inlineAuthenticatedImages(in html: String, baseURL: URL?) async -> String {
        guard let baseURL else { return html }
        let pattern = #"<img\b[^>]*\bsrc\s*=\s*["']([^"']+)["'][^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return html }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: nsRange)
        guard !matches.isEmpty else { return html }

        var replacements: [String: String] = [:]
        for match in matches {
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: html) else { continue }
            let rawSource = String(html[range])
            guard replacements[rawSource] == nil,
                  !rawSource.lowercased().hasPrefix("data:"),
                  let resolved = resolvedURL(from: rawSource, baseURL: baseURL),
                  resolved.host == baseURL.host else { continue }

            do {
                let payload = try await fetchData(url: resolved)
                let encoded = payload.data.base64EncodedString()
                replacements[rawSource] = "data:\(payload.mimeType);base64,\(encoded)"
            } catch {
                continue
            }
        }

        var output = html
        for (source, replacement) in replacements {
            output = output.replacingOccurrences(of: source, with: replacement)
            output = output.replacingOccurrences(of: source.htmlAttributeEscaped(), with: replacement)
        }
        return output
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

    private func requestVoid(_ path: String, method: String) async throws {
        let url = try makeURL(path: path, queryItems: [])
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ConfluenceHot-iOS", forHTTPHeaderField: "User-Agent")
        request.setValue(basicAuthHeader(), forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConfluenceClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            throw ConfluenceClientError.httpStatus(httpResponse.statusCode, message)
        }
    }

    private func fetchSearchItems(cql: String, start: Int, limit: Int, prefersCreatedAuthor: Bool = false) async throws -> [ContentItem] {
        let response: ContentSearchResponse = try await request(
            "/rest/api/content/search",
            queryItems: [
                URLQueryItem(name: "cql", value: cql),
                URLQueryItem(name: "start", value: String(start)),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "expand", value: "space,history.createdBy,history.lastUpdated,body.view")
            ]
        )
        return response.results.map { $0.item(origin: .search, prefersCreatedAuthor: prefersCreatedAuthor) }
    }

    private func searchContentWithAuthorFilter(contentQuery: String, authorQuery: String, start: Int, limit: Int) async throws -> [ContentItem] {
        let authorClauses = try await creatorCQLClauses(for: authorQuery)
        if !authorClauses.isEmpty {
            var filters = ["type in (page,blogpost)", "(\(authorClauses.joined(separator: " or ")))"]
            if !contentQuery.isEmpty {
                let escaped = Self.escapeCQL(contentQuery)
                filters.append("(title ~ \"\(escaped)\" or text ~ \"\(escaped)\")")
            }
            let cql = "\(filters.joined(separator: " and ")) order by lastmodified desc"
            do {
                return try await fetchSearchItems(cql: cql, start: start, limit: limit, prefersCreatedAuthor: true)
                    .filter { Self.matchesAuthor($0, query: authorQuery) && Self.matchesContent($0, query: contentQuery) }
            } catch {
                // Fall back to client-side filtering for older Confluence CQL variants.
            }
        }

        var filters = ["type in (page,blogpost)"]
        if !contentQuery.isEmpty {
            let escaped = Self.escapeCQL(contentQuery)
            filters.append("(title ~ \"\(escaped)\" or text ~ \"\(escaped)\")")
        }
        let cql = "\(filters.joined(separator: " and ")) order by lastmodified desc"

        var rawStart = 0
        var skippedMatches = 0
        var output: [ContentItem] = []
        let rawPageSize = 80
        let maxScanned = contentQuery.isEmpty ? 4000 : 1200

        while output.count < limit && rawStart < maxScanned {
            let page = try await fetchSearchItems(cql: cql, start: rawStart, limit: rawPageSize, prefersCreatedAuthor: true)
            if page.isEmpty { break }
            for item in page {
                guard Self.matchesAuthor(item, query: authorQuery),
                      Self.matchesContent(item, query: contentQuery) else { continue }
                if skippedMatches < start {
                    skippedMatches += 1
                } else {
                    output.append(item)
                    if output.count >= limit { break }
                }
            }
            if page.count < rawPageSize { break }
            rawStart += rawPageSize
        }

        return output
    }

    private func creatorCQLClauses(for authorQuery: String) async throws -> [String] {
        let cleaned = authorQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }

        var creators: [String] = [cleaned]
        do {
            let response: SearchUserResponse = try await request(
                "/rest/api/search/user",
                queryItems: [
                    URLQueryItem(name: "cql", value: "user.fullname ~ \"\(Self.escapeCQL(cleaned))\""),
                    URLQueryItem(name: "limit", value: "20")
                ]
            )
            for result in response.results {
                if let username = result.username ?? result.user?.username {
                    creators.append(username)
                }
                if let userKey = result.user?.userKey {
                    creators.append(userKey)
                }
            }
        } catch {
            // The raw query is still useful when the user types an exact username.
        }

        let uniqueCreators = Array(Set(creators.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })).filter { !$0.isEmpty }
        return uniqueCreators.prefix(20).map { "creator = \"\(Self.escapeCQL($0))\"" }
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

    private static func matchesAuthor(_ item: ContentItem, query: String) -> Bool {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return true }
        return item.authorName?.localizedCaseInsensitiveContains(cleaned) == true
    }

    private static func matchesContent(_ item: ContentItem, query: String) -> Bool {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return true }
        let searchableText = item.searchableText ?? item.excerpt ?? ""
        return item.title.localizedCaseInsensitiveContains(cleaned)
            || searchableText.localizedCaseInsensitiveContains(cleaned)
    }

    private func resolvedURL(from source: String, baseURL: URL) -> URL? {
        let unescaped = source
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
        if let absolute = URL(string: unescaped), absolute.scheme != nil {
            return absolute
        }
        return URL(string: unescaped, relativeTo: baseURL)?.absoluteURL
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "svg":
            return "image/svg+xml"
        default:
            return "image/png"
        }
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

private struct UpdateContentRequest: Encodable {
    let id: String
    let type: String
    let title: String
    let version: ContentVersionRequest
    let body: StorageBody
}

private struct CreateContentRequest: Encodable {
    let type: String
    let title: String
    let space: SpaceKeyRequest
    let body: StorageBody
}

private struct ContentVersionRequest: Encodable {
    let number: Int
}

private struct SpaceKeyRequest: Encodable {
    let key: String
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
    case missingStorageBody
    case missingSpace

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
        case .missingStorageBody:
            return "当前文章缺少可编辑正文"
        case .missingSpace:
            return "当前文章缺少空间信息，无法复制"
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

    func htmlAttributeEscaped() -> String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
