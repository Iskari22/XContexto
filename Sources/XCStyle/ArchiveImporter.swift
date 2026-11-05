import Foundation
import XCCore

/// Importa tu archivo de X (Ajustes → Tu cuenta → Descargar un archivo de tus datos → data/tweets.js).
public enum ArchiveImporter {
    public static func parseTweetsJS(_ data: Data) throws -> [StyleSample] {
        guard var text = String(data: data, encoding: .utf8) else { throw XCError.decoding("tweets.js no es UTF-8") }
        // El archivo empieza con `window.YTD.tweets.part0 = [` — quitamos todo antes del primer '['.
        if let i = text.firstIndex(of: "[") { text = String(text[i...]) }
        let root = try JSONValue.decode(Data(text.utf8))
        guard let items = root.array else { throw XCError.decoding("tweets.js sin lista") }
        return items.compactMap { item in
            let t = item["tweet"] ?? item
            guard let full = t["full_text"]?.string ?? t["text"]?.string else { return nil }
            let likes = Int(t["favorite_count"]?.string ?? "") ?? t["favorite_count"]?.int ?? 0
            let rts = Int(t["retweet_count"]?.string ?? "") ?? t["retweet_count"]?.int ?? 0
            let isReply = t["in_reply_to_status_id_str"]?.string != nil
            // Quita la mención inicial de las respuestas ("@fulano texto") para quedarnos con tu voz.
            let cleaned = full.replacingOccurrences(of: #"^(@\w+\s+)+"#, with: "", options: .regularExpression)
            return StyleSample(text: OEmbedEntities.decode(cleaned), isReply: isReply, likes: likes, retweets: rts, lang: t["lang"]?.string,
                               replyToID: t["in_reply_to_status_id_str"]?.string, replyToHandle: t["in_reply_to_screen_name"]?.string)
        }
    }

    public static func importFile(at url: URL) throws -> [StyleSample] {
        try parseTweetsJS(Data(contentsOf: url))
    }
}

enum OEmbedEntities {
    static func decode(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
    }
}

/// Persistencia del perfil de estilo.
public enum StyleStore {
    static var url: URL { AppStorage.file("style-profile.json") }
    public static func load() -> StyleProfile { JSONFile.load(StyleProfile.self, from: url) ?? .empty }
    public static func save(_ p: StyleProfile) throws { try JSONFile.save(p, to: url) }
}
