import Foundation
import XCCore
import XCSecurity

public struct WikiArticle: Sendable, Hashable {
    public var title: String
    public var extract: String
    public var url: String
}

/// Consulta Wikipedia (API pública) en paralelo a la búsqueda web.
public struct WikipediaClient: Sendable {
    let http: GuardedHTTPClient
    public init(http: GuardedHTTPClient = GuardedHTTPClient()) { self.http = http }

    public func articles(for text: String, lang: String, limit: Int = 3) async -> [WikiArticle] {
        let query = KeywordExtractor.query(from: text)
        guard !query.isEmpty else { return [] }
        let host = "\(lang == "en" ? "en" : "es").wikipedia.org"
        var c = URLComponents(string: "https://\(host)/w/rest.php/v1/search/page")!
        c.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: String(limit))]
        guard let pages = try? await get(c.url!)?["pages"]?.array else { return [] }

        return await withTaskGroup(of: (Int, WikiArticle?).self) { group in
            for (i, page) in pages.prefix(limit).enumerated() {
                guard let key = page["key"]?.string else { continue }
                group.addTask {
                    let enc = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
                    guard let url = URL(string: "https://\(host)/api/rest_v1/page/summary/\(enc)"),
                          let s = try? await get(url), let extract = s["extract"]?.string, !extract.isEmpty else { return (i, nil) }
                    let pageURL = s["content_urls"]?["desktop"]?["page"]?.string ?? "https://\(host)/wiki/\(enc)"
                    return (i, WikiArticle(title: s["title"]?.string ?? key, extract: extract, url: pageURL))
                }
            }
            var out: [(Int, WikiArticle)] = []
            for await (i, a) in group { if let a { out.append((i, a)) } }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func get(_ url: URL) async throws -> JSONValue? {
        var req = URLRequest(url: url, timeoutInterval: 10)
        // Wikimedia pide un User-Agent identificable.
        req.setValue("XContexto/0.1 (app personal; contexto de posts)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await http.data(for: req)
        guard resp.statusCode == 200 else { return nil }
        return try JSONValue.decode(data)
    }
}

/// Saca una consulta de búsqueda de un post: hashtags y nombres propios primero.
public enum KeywordExtractor {
    static let stop: Set<String> = ["El", "La", "Los", "Las", "Un", "Una", "Y", "De", "En", "Que", "The", "A", "An", "This", "Esto",
                                     "Hoy", "Ayer", "Si", "No", "Por", "Para", "Con", "Es", "Lo", "Al", "Del", "Se", "Ya", "RT"]

    public static func query(from text: String, maxTerms: Int = 6) -> String {
        let cleaned = text.replacingOccurrences(of: #"https?://\S+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"@\w+"#, with: " ", options: .regularExpression)
        let words = cleaned.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "#-áéíóúñÁÉÍÓÚÑ")).inverted)
            .filter { !$0.isEmpty }
        var terms: [String] = []
        for w in words {
            let core = w.hasPrefix("#") ? String(w.dropFirst()) : w
            guard core.count > 2, !stop.contains(core) else { continue }
            if w.hasPrefix("#") || core.first?.isUppercase == true || core.allSatisfy({ $0.isUppercase }) {
                if !terms.contains(core) { terms.append(core) }
            }
            if terms.count >= maxTerms { break }
        }
        if terms.count < 2 {
            terms = Array(words.filter { $0.count > 4 }.prefix(maxTerms))
        }
        return terms.joined(separator: " ")
    }
}
