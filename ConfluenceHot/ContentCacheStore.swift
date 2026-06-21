import Foundation

enum ConfluenceCachePolicy {
    case useCache
    case reloadIgnoringCache

    var allowsFreshRead: Bool {
        self == .useCache
    }

    var allowsStaleFallback: Bool {
        true
    }
}

enum ConfluenceContentListKind: String, Codable {
    case recent
    case popular
    case space
    case search
}

struct ConfluenceContentListCacheKey: Hashable {
    let kind: ConfluenceContentListKind
    let start: Int
    let limit: Int
    let spaceKey: String?
    let contentQuery: String?
    let authorQuery: String?

    var storageKey: String {
        [
            kind.rawValue,
            "start=\(start)",
            "limit=\(limit)",
            "space=\(spaceKey ?? "")",
            "content=\(contentQuery ?? "")",
            "author=\(authorQuery ?? "")"
        ].joined(separator: "|")
    }

    static func recent(start: Int, limit: Int) -> ConfluenceContentListCacheKey {
        ConfluenceContentListCacheKey(kind: .recent, start: start, limit: limit, spaceKey: nil, contentQuery: nil, authorQuery: nil)
    }

    static func popular(start: Int, limit: Int) -> ConfluenceContentListCacheKey {
        ConfluenceContentListCacheKey(kind: .popular, start: start, limit: limit, spaceKey: nil, contentQuery: nil, authorQuery: nil)
    }

    static func space(spaceKey: String, start: Int, limit: Int) -> ConfluenceContentListCacheKey {
        ConfluenceContentListCacheKey(kind: .space, start: start, limit: limit, spaceKey: spaceKey, contentQuery: nil, authorQuery: nil)
    }

    static func search(contentQuery: String, authorQuery: String, start: Int, limit: Int) -> ConfluenceContentListCacheKey {
        ConfluenceContentListCacheKey(
            kind: .search,
            start: start,
            limit: limit,
            spaceKey: nil,
            contentQuery: contentQuery,
            authorQuery: authorQuery
        )
    }
}

actor ConfluenceCacheStore {
    static let listMaxAge: TimeInterval = 10 * 60
    static let detailMaxAge: TimeInterval = 60 * 60
    static let commentsMaxAge: TimeInterval = 5 * 60
    static let spacesMaxAge: TimeInterval = 60 * 60
    static let binaryMaxAge: TimeInterval = 7 * 24 * 60 * 60

    private let rootDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(configuration: ServerConfiguration) {
        rootDirectory = Self.rootDirectory(for: configuration)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        decoder = JSONDecoder()
    }

    func cachedContentList(for key: ConfluenceContentListCacheKey, maxAge: TimeInterval? = listMaxAge) -> [ContentItem]? {
        guard let page: CachedContentListPage = read(CachedContentListPage.self, from: url(for: key.storageKey, in: "lists")),
              isFresh(page.storedAt, maxAge: maxAge) else {
            return nil
        }

        let summaries = readSummaryIndex()
        let items = page.itemIDs.compactMap { summaries[$0]?.item(origin: page.origin) }
        guard items.count == page.itemIDs.count else { return nil }
        return items
    }

    func storeContentList(_ items: [ContentItem], for key: ConfluenceContentListCacheKey) {
        var summaries = readSummaryIndex()
        for item in items {
            let incoming = CachedContentSummary(item: item)
            summaries[item.id] = summaries[item.id]?.merged(with: incoming) ?? incoming
        }
        writeSummaryIndex(summaries)

        let page = CachedContentListPage(
            storedAt: Date(),
            storageKey: key.storageKey,
            itemIDs: items.map(\.id),
            origin: items.first?.origin ?? origin(for: key.kind)
        )
        write(page, to: url(for: key.storageKey, in: "lists"))
    }

    func cachedSpaces(start: Int, limit: Int, maxAge: TimeInterval? = spacesMaxAge) -> [ConfluenceSpace]? {
        let key = "spaces|start=\(start)|limit=\(limit)"
        guard let page: CachedSpacesPage = read(CachedSpacesPage.self, from: url(for: key, in: "spaces")),
              isFresh(page.storedAt, maxAge: maxAge) else {
            return nil
        }
        return page.spaces
    }

    func storeSpaces(_ spaces: [ConfluenceSpace], start: Int, limit: Int) {
        let key = "spaces|start=\(start)|limit=\(limit)"
        let page = CachedSpacesPage(storedAt: Date(), storageKey: key, spaces: spaces)
        write(page, to: url(for: key, in: "spaces"))
    }

    func cachedContentDetail(id: String, maxAge: TimeInterval? = detailMaxAge) -> ContentDetail? {
        guard let record: CachedContentDetail = read(CachedContentDetail.self, from: url(for: id, in: "details")),
              isFresh(record.storedAt, maxAge: maxAge) else {
            return nil
        }
        return record.detail
    }

    func storeContentDetail(_ detail: ContentDetail) {
        let record = CachedContentDetail(storedAt: Date(), detail: detail)
        write(record, to: url(for: detail.id, in: "details"))
    }

    func invalidateContentLists(containingContentID id: String) {
        let directory = directory(named: "lists")
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for url in urls where url.pathExtension == "json" {
            guard let page: CachedContentListPage = read(CachedContentListPage.self, from: url),
                  page.itemIDs.contains(id) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    func cachedComments(contentID: String, limit: Int, maxAge: TimeInterval? = commentsMaxAge) -> [CommentItem]? {
        let key = commentsKey(contentID: contentID, limit: limit)
        guard let page: CachedCommentsPage = read(CachedCommentsPage.self, from: url(for: key, in: "comments")),
              isFresh(page.storedAt, maxAge: maxAge) else {
            return nil
        }
        return page.comments
    }

    func storeComments(_ comments: [CommentItem], contentID: String, limit: Int) {
        let key = commentsKey(contentID: contentID, limit: limit)
        let page = CachedCommentsPage(storedAt: Date(), storageKey: key, contentID: contentID, limit: limit, comments: comments)
        write(page, to: url(for: key, in: "comments"))
    }

    func cachedData(for url: URL, maxAge: TimeInterval? = binaryMaxAge) -> (data: Data, mimeType: String)? {
        let key = url.absoluteString
        let metadataURL = self.url(for: key, in: "binaries")
        guard let metadata: CachedBinaryResource = read(CachedBinaryResource.self, from: metadataURL),
              isFresh(metadata.storedAt, maxAge: maxAge) else {
            return nil
        }

        let dataURL = directory(named: "binaries").appendingPathComponent(metadata.dataFileName)
        guard let data = try? Data(contentsOf: dataURL) else { return nil }
        return (data, metadata.mimeType)
    }

    func storeData(_ data: Data, mimeType: String, for url: URL) {
        let key = url.absoluteString
        let fileName = "\(Self.stableHash(key)).data"
        let directory = directory(named: "binaries")
        ensureDirectory(directory)

        do {
            try data.write(to: directory.appendingPathComponent(fileName), options: [.atomic])
            let metadata = CachedBinaryResource(storedAt: Date(), storageKey: key, mimeType: mimeType, dataFileName: fileName)
            write(metadata, to: self.url(for: key, in: "binaries"))
        } catch {
            return
        }
    }

    func invalidateComments(contentID: String) {
        let directory = directory(named: "comments")
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for url in urls where url.pathExtension == "json" {
            guard let page: CachedCommentsPage = read(CachedCommentsPage.self, from: url),
                  page.contentID == contentID else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    func removeContent(id: String) {
        try? FileManager.default.removeItem(at: url(for: id, in: "details"))
        invalidateComments(contentID: id)
        invalidateContentLists(containingContentID: id)

        var summaries = readSummaryIndex()
        summaries.removeValue(forKey: id)
        writeSummaryIndex(summaries)
    }

    private func readSummaryIndex() -> [String: CachedContentSummary] {
        read([String: CachedContentSummary].self, from: rootDirectory.appendingPathComponent("content-summaries.json")) ?? [:]
    }

    private func writeSummaryIndex(_ summaries: [String: CachedContentSummary]) {
        write(summaries, to: rootDirectory.appendingPathComponent("content-summaries.json"))
    }

    private func commentsKey(contentID: String, limit: Int) -> String {
        "comments|\(contentID)|limit=\(limit)"
    }

    private func origin(for kind: ConfluenceContentListKind) -> ContentItem.Origin {
        switch kind {
        case .popular:
            return .popular
        case .search:
            return .search
        case .recent, .space:
            return .recent
        }
    }

    private func isFresh(_ storedAt: Date, maxAge: TimeInterval?) -> Bool {
        guard let maxAge else { return true }
        return Date().timeIntervalSince(storedAt) <= maxAge
    }

    private func url(for key: String, in directoryName: String) -> URL {
        directory(named: directoryName).appendingPathComponent("\(Self.stableHash(key)).json")
    }

    private func directory(named name: String) -> URL {
        rootDirectory.appendingPathComponent(name, isDirectory: true)
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        ensureDirectory(url.deletingLastPathComponent())
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private static func rootDirectory(for configuration: ServerConfiguration) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let namespace = stableHash("\(configuration.baseURL.absoluteString)|\(configuration.username.lowercased())")
        return base
            .appendingPathComponent("ConfluenceHotCache", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
            .appendingPathComponent(namespace, isDirectory: true)
    }

    private static func stableHash(_ value: String) -> String {
        let bytes = value.utf8
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

private struct CachedContentListPage: Codable {
    let storedAt: Date
    let storageKey: String
    let itemIDs: [String]
    let origin: ContentItem.Origin
}

private struct CachedContentSummary: Codable {
    let id: String
    let title: String
    let type: String
    let spaceName: String?
    let authorName: String?
    let authorAvatarPath: String?
    let dateText: String?
    let date: Date?
    let webPath: String?
    let likeCount: Int?
    let commentCount: Int?
    let excerpt: String?
    let searchableText: String?

    init(item: ContentItem) {
        id = item.id
        title = item.title
        type = item.type
        spaceName = item.spaceName
        authorName = item.authorName
        authorAvatarPath = item.authorAvatarPath
        dateText = item.dateText
        date = item.date
        webPath = item.webPath
        likeCount = item.likeCount
        commentCount = item.commentCount
        excerpt = item.excerpt
        searchableText = item.searchableText
    }

    func item(origin: ContentItem.Origin) -> ContentItem {
        ContentItem(
            id: id,
            title: title,
            type: type,
            spaceName: spaceName,
            authorName: authorName,
            authorAvatarPath: authorAvatarPath,
            dateText: dateText,
            date: date,
            webPath: webPath,
            likeCount: likeCount,
            commentCount: commentCount,
            excerpt: excerpt,
            searchableText: searchableText,
            origin: origin
        )
    }

    func merged(with incoming: CachedContentSummary) -> CachedContentSummary {
        CachedContentSummary(
            id: id,
            title: incoming.title.isEmpty ? title : incoming.title,
            type: incoming.type.isEmpty ? type : incoming.type,
            spaceName: incoming.spaceName ?? spaceName,
            authorName: incoming.authorName ?? authorName,
            authorAvatarPath: incoming.authorAvatarPath ?? authorAvatarPath,
            dateText: incoming.dateText ?? dateText,
            date: newestDate(between: date, and: incoming.date),
            webPath: incoming.webPath ?? webPath,
            likeCount: incoming.likeCount ?? likeCount,
            commentCount: incoming.commentCount ?? commentCount,
            excerpt: incoming.excerpt ?? excerpt,
            searchableText: incoming.searchableText ?? searchableText
        )
    }

    private init(
        id: String,
        title: String,
        type: String,
        spaceName: String?,
        authorName: String?,
        authorAvatarPath: String?,
        dateText: String?,
        date: Date?,
        webPath: String?,
        likeCount: Int?,
        commentCount: Int?,
        excerpt: String?,
        searchableText: String?
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.spaceName = spaceName
        self.authorName = authorName
        self.authorAvatarPath = authorAvatarPath
        self.dateText = dateText
        self.date = date
        self.webPath = webPath
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.excerpt = excerpt
        self.searchableText = searchableText
    }

    private func newestDate(between current: Date?, and incoming: Date?) -> Date? {
        guard let current else { return incoming }
        guard let incoming else { return current }
        return incoming > current ? incoming : current
    }
}

private struct CachedSpacesPage: Codable {
    let storedAt: Date
    let storageKey: String
    let spaces: [ConfluenceSpace]
}

private struct CachedContentDetail: Codable {
    let storedAt: Date
    let detail: ContentDetail
}

private struct CachedCommentsPage: Codable {
    let storedAt: Date
    let storageKey: String
    let contentID: String
    let limit: Int
    let comments: [CommentItem]
}

private struct CachedBinaryResource: Codable {
    let storedAt: Date
    let storageKey: String
    let mimeType: String
    let dataFileName: String
}
