import Foundation
import XCCore

/// La única forma en que un borrador sale de la app: copiarlo, o abrir la ventana de X
/// con el texto ya escrito. En ambos casos **eres tú** quien pulsa "Publicar" dentro de X.
public enum PostingGuard {
    /// URL de la ventana de redacción de X (web intent). No publica: solo abre el editor de X.
    public static func composeURL(reply text: String, inReplyTo postID: String?) -> URL {
        var c = URLComponents(string: "https://x.com/intent/post")!
        var items = [URLQueryItem(name: "text", value: text)]
        if let id = postID, id.allSatisfy(\.isNumber) { items.append(URLQueryItem(name: "in_reply_to", value: id)) }
        c.queryItems = items
        return c.url!
    }

    /// Número de caracteres tal como los cuenta X (las URLs cuentan 23).
    public static func xLength(_ text: String) -> Int {
        let pattern = #"https?://\S+"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return text.count }
        let ns = text as NSString
        var length = text.count
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            length += 23 - ns.substring(with: m.range).count
        }
        return length
    }
}

/// Quita secretos de cualquier texto antes de guardarlo en logs o informes.
public enum Redactor {
    public static func redact(_ s: String) -> String {
        var out = s
        let patterns = [#"sk-ant-[A-Za-z0-9_\-]{8,}"#, #"(?i)x-api-key:\s*\S+"#, #"(?i)bearer\s+[A-Za-z0-9._\-]+"#]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p) {
                out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "[REDACTADO]")
            }
        }
        return out
    }
}
