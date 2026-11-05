import Foundation

/// Reconoce URLs de posts de X/Twitter: https://x.com/usuario/status/123…
public struct PostURL: Sendable, Hashable {
    public let handle: String
    public let id: String

    private static let hosts: Set<String> = [
        "x.com", "www.x.com", "mobile.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com",
    ]

    public init?(_ url: URL) {
        guard let host = url.host?.lowercased(), Self.hosts.contains(host) else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard let i = parts.firstIndex(where: { $0 == "status" || $0 == "statuses" }), i >= 1, i + 1 < parts.count
        else { return nil }
        let id = parts[i + 1]
        guard !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
        self.handle = parts[i - 1]
        self.id = id
    }

    public init?(string: String) {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        self.init(url)
    }

    public var canonicalURL: URL { URL(string: "https://x.com/\(handle)/status/\(id)")! }
}
