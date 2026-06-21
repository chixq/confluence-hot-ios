import Foundation

struct ServerConfiguration: Codable, Equatable {
    let baseURL: URL
    let username: String

    var keychainAccount: String {
        "\(baseURL.absoluteString)|\(username)"
    }

    static func normalized(baseURL rawBaseURL: String, username rawUsername: String) throws -> ServerConfiguration {
        let trimmedURL = rawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = rawUsername.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedURL.isEmpty else { throw ConfluenceClientError.invalidBaseURL }
        guard !trimmedUsername.isEmpty else { throw ConfluenceClientError.missingUsername }

        let candidate = trimmedURL.contains("://") ? trimmedURL : "https://\(trimmedURL)"
        guard var components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host?.isEmpty == false else {
            throw ConfluenceClientError.invalidBaseURL
        }

        components.scheme = scheme
        components.query = nil
        components.fragment = nil
        components.percentEncodedPath = components.percentEncodedPath.trimmedTrailingSlashes()

        guard let normalizedURL = components.url else {
            throw ConfluenceClientError.invalidBaseURL
        }

        return ServerConfiguration(baseURL: normalizedURL, username: trimmedUsername)
    }
}

struct UserProfile: Codable, Equatable {
    let type: String?
    let username: String?
    let userKey: String?
    let displayName: String
    let profilePicture: ProfilePicture?
    let links: Links?

    var stableID: String {
        userKey ?? username ?? displayName
    }

    enum CodingKeys: String, CodingKey {
        case type
        case username
        case userKey
        case displayName
        case profilePicture
        case links = "_links"
    }
}

struct ProfilePicture: Codable, Equatable {
    let path: String?
    let width: Int?
    let height: Int?
    let isDefault: Bool?
}

struct Links: Codable, Equatable {
    let base: String?
    let context: String?
    let selfLink: String?
    let webUI: String?
    let tinyUI: String?

    enum CodingKeys: String, CodingKey {
        case base
        case context
        case selfLink = "self"
        case webUI = "webui"
        case tinyUI = "tinyui"
    }
}

struct ContentItem: Identifiable, Codable, Equatable {
    enum Origin: String, Codable, Equatable {
        case recent
        case popular
        case search
    }

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
    let origin: Origin

    var typeLabel: String {
        switch type.lowercased() {
        case "blogpost", "blog":
            return "博客"
        default:
            return "页面"
        }
    }

    var activitySummary: String {
        var pieces: [String] = []
        if let likeCount {
            pieces.append("\(likeCount) 赞")
        }
        if let commentCount {
            pieces.append("\(commentCount) 评论")
        }
        if let dateText, !dateText.isEmpty {
            pieces.append(dateText)
        }
        return pieces.joined(separator: " · ")
    }

    func webURL(baseURL: URL) -> URL? {
        guard let webPath, !webPath.isEmpty else { return nil }
        if let absolute = URL(string: webPath), absolute.scheme != nil {
            return absolute
        }
        return URL(string: webPath, relativeTo: baseURL)?.absoluteURL
    }
}

struct ContentSearchResponse: Decodable {
    let results: [ContentSearchResult]
    let size: Int?
    let start: Int?
    let limit: Int?
    let totalSize: Int?

    var hasMore: Bool {
        guard let size, let limit else { return results.count >= 30 }
        return size >= limit
    }
}

struct ContentSearchResult: Decodable {
    let id: String
    let type: String
    let status: String?
    let title: String
    let space: ConfluenceSpace?
    let history: ContentHistory?
    let body: ContentBody?
    let version: ContentVersion?
    let links: Links?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case status
        case title
        case space
        case history
        case body
        case version
        case links = "_links"
    }

    func item(origin: ContentItem.Origin) -> ContentItem {
        let update = history?.lastUpdated
        let created = history?.createdBy
        let dateString = update?.friendlyWhen ?? update?.when ?? history?.createdDate
        let parsedDate = DateParser.parse(update?.when ?? history?.createdDate)
        let fullText = body?.view?.value.strippedHTMLText()

        return ContentItem(
            id: id,
            title: title,
            type: type,
            spaceName: space?.name,
            authorName: update?.by?.displayName ?? created?.displayName,
            authorAvatarPath: update?.by?.profilePicture?.path ?? created?.profilePicture?.path,
            dateText: DateParser.displayText(from: dateString, date: parsedDate),
            date: parsedDate,
            webPath: links?.webUI ?? links?.tinyUI,
            likeCount: nil,
            commentCount: nil,
            excerpt: fullText?.limited(to: 160),
            searchableText: fullText,
            origin: origin
        )
    }

    func detail() -> ContentDetail {
        ContentDetail(
            id: id,
            type: type,
            title: title,
            space: space,
            body: body,
            version: version,
            links: links
        )
    }
}

struct ContentHistory: Codable {
    let latest: Bool?
    let createdBy: UserSummary?
    let createdDate: String?
    let lastUpdated: ContentVersion?
}

struct ContentVersion: Codable {
    let by: UserSummary?
    let when: String?
    let friendlyWhen: String?
    let number: Int?
    let message: String?
}

struct UserSummary: Codable, Equatable {
    let type: String?
    let username: String?
    let userKey: String?
    let displayName: String?
    let profilePicture: ProfilePicture?
}

struct ConfluenceSpace: Codable, Identifiable, Equatable {
    let id: Int?
    let key: String
    let name: String
    let type: String?
    let links: Links?

    enum CodingKeys: String, CodingKey {
        case id
        case key
        case name
        case type
        case links = "_links"
    }
}

struct SpaceResponse: Decodable {
    let results: [ConfluenceSpace]
    let size: Int?
    let start: Int?
    let limit: Int?

    var hasMore: Bool {
        guard let size, let limit else { return results.count >= 50 }
        return size >= limit
    }
}

struct PopularStreamResponse: Decodable {
    let streamItems: [PopularStreamItem]
}

struct PopularStreamItem: Decodable {
    let id: Int
    let title: String
    let url: String?
    let author: PopularAuthor?
    let friendlyDate: String?
    let date: String?
    let numberOfLikes: Int?
    let numberOfComments: Int?
    let contentCssClass: String?

    var contentType: String {
        if contentCssClass?.contains("blog") == true {
            return "blogpost"
        }
        return "page"
    }

    func item() -> ContentItem {
        let parsedDate = DateParser.parse(date)

        return ContentItem(
            id: String(id),
            title: title,
            type: contentType,
            spaceName: nil,
            authorName: author?.fullName ?? author?.userName,
            authorAvatarPath: author?.avatarUrl,
            dateText: DateParser.displayText(from: friendlyDate ?? date, date: parsedDate),
            date: parsedDate,
            webPath: url,
            likeCount: numberOfLikes,
            commentCount: numberOfComments,
            excerpt: nil,
            searchableText: nil,
            origin: .popular
        )
    }
}

struct PopularAuthor: Decodable {
    let userName: String?
    let fullName: String?
    let avatarUrl: String?
}

struct ContentDetail: Codable {
    let id: String
    let type: String
    let title: String
    let space: ConfluenceSpace?
    let body: ContentBody?
    let version: ContentVersion?
    let links: Links?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case space
        case body
        case version
        case links = "_links"
    }

    var renderedHTML: String {
        body?.view?.value ?? "<p></p>"
    }

    var storageHTML: String? {
        body?.storage?.value
    }

    var nextVersionNumber: Int {
        (version?.number ?? 1) + 1
    }
}

struct ContentBody: Codable {
    let view: BodyRepresentation?
    let storage: BodyRepresentation?
}

struct BodyRepresentation: Codable {
    let value: String
    let representation: String?
}

struct CommentResponse: Decodable {
    let results: [CommentResult]
}

struct CommentResult: Decodable {
    let id: String
    let type: String?
    let title: String?
    let body: ContentBody?
    let history: ContentHistory?
    let version: ContentVersion?
    let links: Links?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case body
        case history
        case version
        case links = "_links"
    }

    func item() -> CommentItem {
        let update = version
        let created = history?.createdBy
        let dateString = update?.friendlyWhen ?? update?.when ?? history?.createdDate
        let parsedDate = DateParser.parse(update?.when ?? history?.createdDate)

        return CommentItem(
            id: id,
            authorName: update?.by?.displayName ?? created?.displayName ?? "匿名用户",
            authorAvatarPath: update?.by?.profilePicture?.path ?? created?.profilePicture?.path,
            dateText: DateParser.displayText(from: dateString, date: parsedDate),
            html: body?.view?.value ?? body?.storage?.value ?? "",
            webPath: links?.webUI ?? links?.tinyUI
        )
    }
}

struct CommentItem: Identifiable, Codable, Equatable {
    let id: String
    let authorName: String
    let authorAvatarPath: String?
    let dateText: String?
    let html: String
    let webPath: String?
}

struct SearchUserResponse: Decodable {
    let results: [SearchUserResult]
    let size: Int?
    let start: Int?
    let limit: Int?
    let totalSize: Int?
}

struct SearchUserResult: Decodable {
    let user: UserSummary?
    let username: String?
    let displayName: String?
}

struct AdminSystemInfo: Equatable {
    let generatedAt: Date
    let userCount: Int?
    let pageCount: Int?
    let blogPostCount: Int?
    let loginAuditCount: Int?
    let rawSystemInfo: [String: String]
}

struct TodoItem: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var isDone: Bool
}

struct TodoPage {
    let detail: ContentDetail
    let todos: [TodoItem]

    init(detail: ContentDetail) {
        self.detail = detail
        self.todos = Self.parseTodos(from: detail.storageHTML ?? detail.renderedHTML)
    }

    static func storageHTML(for todos: [TodoItem]) -> String {
        let rows = todos.map { item in
            "<li data-id=\"\(item.id.htmlAttributeEscaped())\" data-done=\"\(item.isDone ? "true" : "false")\">\(item.title.htmlEscaped())</li>"
        }
        .joined()

        return """
        <p><strong>Confluence Hot 待办</strong></p>
        <p>这个页面由 Confluence Hot iOS 维护，用于保存当前账号的私人待办列表。</p>
        <ul data-confluence-hot-todos="true">\(rows)</ul>
        """
    }

    private static func parseTodos(from html: String) -> [TodoItem] {
        let pattern = #"<li\b([^>]*)>(.*?)</li>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, options: [], range: nsRange).compactMap { match in
            guard match.numberOfRanges > 2,
                  let attributesRange = Range(match.range(at: 1), in: html),
                  let bodyRange = Range(match.range(at: 2), in: html) else { return nil }

            let attributes = String(html[attributesRange])
            let title = String(html[bodyRange]).strippedHTMLText()
            guard !title.isEmpty else { return nil }
            let id = Self.attribute("data-id", in: attributes) ?? UUID().uuidString
            let doneText = Self.attribute("data-done", in: attributes) ?? "false"
            return TodoItem(id: id, title: title, isDone: doneText == "true")
        }
    }

    private static func attribute(_ name: String, in attributes: String) -> String? {
        let pattern = #"\#(name)\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsRange = NSRange(attributes.startIndex..<attributes.endIndex, in: attributes)
        guard let match = regex.firstMatch(in: attributes, options: [], range: nsRange),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: attributes) else { return nil }
        return String(attributes[range])
    }
}

struct GenericCountResponse: Decodable {
    let size: Int?
    let totalSize: Int?
    let totalCount: Int?
    let results: [JSONValue]?

    var countValue: Int? {
        totalSize ?? totalCount ?? size ?? results?.count
    }
}

enum JSONValue: Decodable, Equatable, CustomStringConvertible {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    var description: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .object(let value):
            return "\(value.count) 项"
        case .array(let value):
            return "\(value.count) 项"
        case .null:
            return ""
        }
    }
}

enum DateParser {
    private static let isoWithColon: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoWithoutFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let confluenceFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return isoWithColon.date(from: value)
            ?? isoWithoutFraction.date(from: value)
            ?? confluenceFormatter.date(from: value)
    }

    static func displayText(from rawText: String?, date: Date?) -> String? {
        if let rawText, !rawText.isEmpty, DateParser.parse(rawText) == nil {
            return rawText
        }
        if let date {
            return displayFormatter.string(from: date)
        }
        return rawText
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

    func strippedHTMLText() -> String {
        let withoutTags = replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let decoded = withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
        let collapsed = decoded
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed
    }

    func limited(to maxLength: Int) -> String {
        guard count > maxLength else { return self }
        return String(prefix(maxLength)) + "..."
    }

    func htmlEscaped() -> String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    func htmlAttributeEscaped() -> String {
        htmlEscaped()
    }
}
