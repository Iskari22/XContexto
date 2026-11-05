import Foundation
import XCCore
import XCSecurity

/// Obtiene el texto de un post. Primero usa el texto que ya trae la extensión o el menú Compartir;
/// si no hay, usa el endpoint público oEmbed de X (solo lectura, sin cuenta ni API de pago).
public struct PostFetcher: Sendable {
    let http: GuardedHTTPClient
    public init(http: GuardedHTTPClient = GuardedHTTPClient()) { self.http = http }

    public func resolve(_ input: PostInput) async throws -> XPost {
        let parsed = input.url.flatMap(PostURL.init)
        if let text = input.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return XPost(id: parsed?.id ?? UUID().uuidString, url: parsed?.canonicalURL ?? input.url,
                         authorName: input.authorName ?? parsed?.handle ?? "",
                         handle: input.handle ?? parsed?.handle ?? "", text: text, lang: LanguageGuess.guess(text))
        }
        guard let p = parsed else { throw XCError.invalidPostURL(input.url?.absoluteString ?? "(vacía)") }

        var c = URLComponents(string: "https://publish.x.com/oembed")!
        c.queryItems = [URLQueryItem(name: "url", value: p.canonicalURL.absoluteString),
                        URLQueryItem(name: "omit_script", value: "true"),
                        URLQueryItem(name: "dnt", value: "true")]
        var req = URLRequest(url: c.url!, timeoutInterval: 15)
        req.httpMethod = "GET"
        let (data, resp) = try await http.data(for: req)
        guard resp.statusCode == 200 else { throw XCError.postUnavailable("oEmbed \(resp.statusCode)") }
        let json = try JSONValue.decode(data)
        let html = json["html"]?.string ?? ""
        let text = OEmbedParser.tweetText(fromHTML: html)
        guard !text.isEmpty else { throw XCError.postUnavailable("post sin texto") }
        return XPost(id: p.id, url: p.canonicalURL, authorName: json["author_name"]?.string ?? p.handle,
                     handle: p.handle, text: text, lang: OEmbedParser.lang(fromHTML: html) ?? LanguageGuess.guess(text))
    }
}

public enum OEmbedParser {
    public static func lang(fromHTML html: String) -> String? {
        guard let r = html.range(of: #"<p lang="([a-z]{2,3})"#, options: .regularExpression) else { return nil }
        return String(html[r].dropFirst(9).dropLast(0)).replacingOccurrences(of: "\"", with: "")
    }

    /// El HTML de oEmbed es `<blockquote><p lang="es">TEXTO</p>&mdash; Autor …</blockquote>`.
    public static func tweetText(fromHTML html: String) -> String {
        guard let pStart = html.range(of: "<p"), let gt = html.range(of: ">", range: pStart.upperBound..<html.endIndex),
              let pEnd = html.range(of: "</p>", range: gt.upperBound..<html.endIndex) else { return "" }
        var inner = String(html[gt.upperBound..<pEnd.lowerBound])
        inner = inner.replacingOccurrences(of: "<br>", with: "\n").replacingOccurrences(of: "<br/>", with: "\n")
        inner = inner.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return decodeEntities(inner).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ s: String) -> String {
        var out = s
        let map = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&mdash;": "—", "&nbsp;": " "]
        for (k, v) in map { out = out.replacingOccurrences(of: k, with: v) }
        // Entidades numéricas: &#123; y &#x1F600;
        if let re = try? NSRegularExpression(pattern: "&#(x?)([0-9A-Fa-f]+);") {
            let ns = out as NSString
            var result = ""
            var last = 0
            for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let hex = ns.substring(with: m.range(at: 1)) == "x"
                let num = ns.substring(with: m.range(at: 2))
                if let v = UInt32(num, radix: hex ? 16 : 10), let sc = Unicode.Scalar(v) { result += String(Character(sc)) }
                last = m.range.location + m.range.length
            }
            result += ns.substring(from: last)
            out = result
        }
        return out
    }
}

public enum LanguageGuess {
    public static func guess(_ text: String) -> String {
        let lower = " " + text.lowercased() + " "
        let es = [" el ", " la ", " de ", " que ", " los ", " las ", " por ", " para ", " con ", " una ", " es "]
        let en = [" the ", " and ", " of ", " to ", " is ", " that ", " for ", " with ", " on "]
        let se = es.reduce(0) { $0 + lower.components(separatedBy: $1).count - 1 }
        let sn = en.reduce(0) { $0 + lower.components(separatedBy: $1).count - 1 }
        return sn > se ? "en" : "es"
    }
}
