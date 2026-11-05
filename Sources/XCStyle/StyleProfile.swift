import Foundation
import XCCore

public struct StyleSample: Codable, Sendable, Hashable {
    public var text: String
    public var isReply: Bool
    public var likes: Int
    public var retweets: Int
    public var lang: String?
    /// Post al que respondías (para calibrar la app con tus respuestas reales).
    public var replyToID: String?
    public var replyToHandle: String?
    public init(text: String, isReply: Bool, likes: Int = 0, retweets: Int = 0, lang: String? = nil,
                replyToID: String? = nil, replyToHandle: String? = nil) {
        self.text = text; self.isReply = isReply; self.likes = likes; self.retweets = retweets; self.lang = lang
        self.replyToID = replyToID; self.replyToHandle = replyToHandle
    }
}

/// Tu estilo de escritura, calculado a partir de tus propios posts.
public struct StyleProfile: Codable, Sendable, Hashable {
    public var sampleCount: Int
    public var medianLength: Int
    public var emojiRate: Double
    public var hashtagRate: Double
    public var questionRate: Double
    public var exclamationRate: Double
    public var linkRate: Double
    public var startsLowercaseRate: Double
    public var signaturePhrases: [String]
    public var samples: [StyleSample]
    /// Notas que escribes tú (p. ej. "nunca uso emojis", "tuteo siempre").
    public var manualNotes: String
    /// Guía de estilo aprendida al comparar borradores con tus respuestas reales (calibración).
    public var learnedGuide: String?

    public static let empty = StyleProfile(sampleCount: 0, medianLength: 200, emojiRate: 0, hashtagRate: 0, questionRate: 0,
                                           exclamationRate: 0, linkRate: 0, startsLowercaseRate: 0, signaturePhrases: [],
                                           samples: [], manualNotes: "", learnedGuide: nil)

    public static func build(from all: [StyleSample], manualNotes: String = "") -> StyleProfile {
        let s = all.filter { !$0.text.hasPrefix("RT @") && $0.text.count > 15 }
        guard !s.isEmpty else { var e = StyleProfile.empty; e.manualNotes = manualNotes; return e }
        func rate(_ p: (String) -> Bool) -> Double { Double(s.filter { p($0.text) }.count) / Double(s.count) }
        let lengths = s.map { $0.text.count }.sorted()
        // Las mejores muestras: tus posts con más interacción, primando respuestas.
        let best = s.sorted { ($0.likes + 2 * $0.retweets + ($0.isReply ? 5 : 0)) > ($1.likes + 2 * $1.retweets + ($1.isReply ? 5 : 0)) }
        return StyleProfile(
            sampleCount: s.count,
            medianLength: lengths[lengths.count / 2],
            emojiRate: rate { $0.unicodeScalars.contains { $0.properties.isEmojiPresentation } },
            hashtagRate: rate { $0.contains("#") },
            questionRate: rate { $0.contains("?") },
            exclamationRate: rate { $0.contains("!") },
            linkRate: rate { $0.contains("http") },
            startsLowercaseRate: rate { $0.first?.isLowercase == true },
            signaturePhrases: signature(s.map(\.text)),
            samples: Array(best.prefix(300)),
            manualNotes: manualNotes,
            learnedGuide: nil
        )
    }

    /// Expresiones de 2-3 palabras que repites a menudo.
    static func signature(_ texts: [String]) -> [String] {
        var counts: [String: Int] = [:]
        let stop: Set<String> = ["de la", "en el", "en la", "de los", "que el", "que la", "a la", "de las", "por el", "con el", "y el", "es un", "es una", "of the", "in the"]
        for t in texts {
            let w = t.lowercased().replacingOccurrences(of: #"https?://\S+|@\w+"#, with: "", options: .regularExpression)
                .split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init)
            guard w.count > 2 else { continue }
            for i in 0..<(w.count - 1) {
                let bi = w[i] + " " + w[i + 1]
                if !stop.contains(bi), bi.count > 6 { counts[bi, default: 0] += 1 }
            }
        }
        let minHits = max(3, texts.count / 80)
        return counts.filter { $0.value >= minHits }.sorted { $0.value > $1.value }.prefix(12).map(\.key)
    }

    /// Ejemplos de tu estilo relevantes para el tema del post (coincidencia de palabras).
    public func exemplars(for text: String, count: Int = 8) -> [StyleSample] {
        guard !samples.isEmpty else { return [] }
        let words = Set(text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count > 4 })
        let scored = samples.enumerated().map { (i, s) -> (Double, StyleSample) in
            let sw = Set(s.text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
            let overlap = Double(words.intersection(sw).count)
            return (overlap * 3 + (s.isReply ? 1 : 0) - Double(i) * 0.001, s)
        }
        return scored.sorted { $0.0 > $1.0 }.prefix(count).map(\.1)
    }

    public func promptDescription() -> String {
        guard sampleCount > 0 || !manualNotes.isEmpty else {
            return "Aún no tengo muestras de su estilo: escribe claro, directo y natural, como una persona informada en X."
        }
        var lines: [String] = []
        if sampleCount > 0 {
            lines.append("Analizados \(sampleCount) posts suyos. Longitud típica: ~\(medianLength) caracteres.")
            lines.append(String(format: "Emojis en %.0f%% de posts, hashtags en %.0f%%, preguntas en %.0f%%, exclamaciones en %.0f%%.",
                                emojiRate * 100, hashtagRate * 100, questionRate * 100, exclamationRate * 100))
            if startsLowercaseRate > 0.4 { lines.append("Suele empezar en minúscula.") }
            if !signaturePhrases.isEmpty { lines.append("Expresiones habituales: \(signaturePhrases.prefix(8).joined(separator: ", ")).") }
        }
        if !manualNotes.isEmpty { lines.append("Indicaciones del propio usuario: \(manualNotes)") }
        if let g = learnedGuide, !g.isEmpty { lines.append("Guía de estilo aprendida de sus respuestas reales:\n\(g)") }
        return lines.joined(separator: "\n")
    }
}
