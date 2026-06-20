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

struct UserProfile: Decodable, Equatable {
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

struct ProfilePicture: Decodable, Equatable {
    let path: String?
    let width: Int?
    let height: Int?
    let isDefault: Bool?
}

struct Links: Decodable, Equatable {
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

struct ContentItem: Identifiable, Equatable {
    enum Origin: Equatable {
        case recent
        case popular
        case search
    }

    let id: String
    let title: String
    let type: String
    let spaceName: String?
    let authorName: String?
    let dateText: String?
    let date: Date?
    let webPath: String?
    let likeCount: Int?
    let commentCount: Int?
    let excerpt: String?
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
}

struct ContentSearchResult: Decodable {
    let id: String
    let type: String
    let status: String?
    let title: String
    let space: ConfluenceSpace?
    let history: ContentHistory?
    let links: Links?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case status
        case title
        case space
        case history
        case links = "_links"
    }

    func item(origin: ContentItem.Origin) -> ContentItem {
        let update = history?.lastUpdated
        let created = history?.createdBy
        let dateString = update?.friendlyWhen ?? update?.when ?? history?.createdDate
        let parsedDate = DateParser.parse(update?.when ?? history?.createdDate)

        return ContentItem(
            id: id,
            title: title,
            type: type,
            spaceName: space?.name,
            authorName: update?.by?.displayName ?? created?.displayName,
            dateText: DateParser.displayText(from: dateString, date: parsedDate),
            date: parsedDate,
            webPath: links?.webUI ?? links?.tinyUI,
            likeCount: nil,
            commentCount: nil,
            excerpt: nil,
            origin: origin
        )
    }
}

struct ContentHistory: Decodable {
    let latest: Bool?
    let createdBy: UserSummary?
    let createdDate: String?
    let lastUpdated: ContentVersion?
}

struct ContentVersion: Decodable {
    let by: UserSummary?
    let when: String?
    let friendlyWhen: String?
    let number: Int?
    let message: String?
}

struct UserSummary: Decodable, Equatable {
    let type: String?
    let username: String?
    let userKey: String?
    let displayName: String?
    let profilePicture: ProfilePicture?
}

struct ConfluenceSpace: Decodable, Identifiable, Equatable {
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
            dateText: DateParser.displayText(from: friendlyDate ?? date, date: parsedDate),
            date: parsedDate,
            webPath: url,
            likeCount: numberOfLikes,
            commentCount: numberOfComments,
            excerpt: nil,
            origin: .popular
        )
    }
}

struct PopularAuthor: Decodable {
    let userName: String?
    let fullName: String?
    let avatarUrl: String?
}

struct ContentDetail: Decodable {
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
}

struct ContentBody: Decodable {
    let view: BodyRepresentation?
    let storage: BodyRepresentation?
}

struct BodyRepresentation: Decodable {
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
            dateText: DateParser.displayText(from: dateString, date: parsedDate),
            html: body?.view?.value ?? body?.storage?.value ?? "",
            webPath: links?.webUI ?? links?.tinyUI
        )
    }
}

struct CommentItem: Identifiable, Equatable {
    let id: String
    let authorName: String
    let dateText: String?
    let html: String
    let webPath: String?
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
}
