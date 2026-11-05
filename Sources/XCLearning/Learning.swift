import Foundation
import XCCore

/// Lo que haces con cada análisis. Todo se queda en tu dispositivo.
public enum InteractionKind: String, Codable, Sendable {
    case opened          // abriste el panel de contexto
    case shown           // se te mostraron los borradores
    case viewedSources   // abriste una fuente
    case copied          // copiaste un borrador
    case composed        // abriste X con el borrador ya escrito
    case edited          // editaste un borrador antes de usarlo
    case regenerated     // pediste otra versión
    case thumbsUp, thumbsDown
    case dismissed       // cerraste sin usar nada
}

public struct InteractionEvent: Codable, Sendable, Hashable {
    public var date: Date
    public var kind: InteractionKind
    public var postID: String
    public var topic: String
    public var stance: DraftStance?
    public var originalText: String?
    public var finalText: String?

    public init(date: Date = Date(), kind: InteractionKind, postID: String, topic: String, stance: DraftStance? = nil,
                originalText: String? = nil, finalText: String? = nil) {
        self.date = date; self.kind = kind; self.postID = postID; self.topic = topic; self.stance = stance
        self.originalText = originalText; self.finalText = finalText
    }
}

/// Modelo de preferencias: aprende qué tipo de respuesta eliges y cómo la editas.
///
/// - Para cada postura (neutro/a favor/crítico) mantiene una distribución Beta(α, β):
///   éxito = la usaste (copiar/abrir en X/👍), fracaso = se mostró y no la usaste (o 👎).
/// - Lo mismo por tema, para que aprenda que, p. ej., en geopolítica prefieres refutar.
/// - Aprende tu longitud preferida a partir del texto final que usas.
public struct PreferenceModel: Codable, Sendable, Hashable {
    public struct Beta: Codable, Sendable, Hashable {
        public var a: Double = 1, b: Double = 1
        public var mean: Double { a / (a + b) }
        public var count: Double { a + b - 2 }
    }

    public var global: [DraftStance: Beta] = [:]
    public var byTopic: [String: [DraftStance: Beta]] = [:]
    public var preferredLength: Double? = nil
    public var recentEdits: [EditPair] = []
    public var totals: [InteractionKind: Int] = [:]

    public struct EditPair: Codable, Sendable, Hashable { public var before: String; public var after: String }

    public init() {}

    static func topicKey(_ t: String) -> String {
        t.lowercased().split(whereSeparator: { !$0.isLetter }).prefix(2).joined(separator: " ")
    }

    public mutating func record(_ e: InteractionEvent) {
        totals[e.kind, default: 0] += 1
        let tk = Self.topicKey(e.topic)
        func bump(_ s: DraftStance, success: Bool, weight: Double = 1) {
            var g = global[s] ?? Beta(); var t = byTopic[tk]?[s] ?? Beta()
            if success { g.a += weight; t.a += weight } else { g.b += weight; t.b += weight }
            global[s] = g; byTopic[tk, default: [:]][s] = t
        }
        switch e.kind {
        case .copied, .composed:
            if let s = e.stance {
                bump(s, success: true)
                // Las otras posturas mostradas y no elegidas cuentan como fracaso suave.
                for o in DraftStance.allCases where o != s { bump(o, success: false, weight: 0.35) }
            }
            if let f = e.finalText {
                let len = Double(f.count)
                preferredLength = preferredLength.map { $0 * 0.8 + len * 0.2 } ?? len
            }
        case .thumbsUp: if let s = e.stance { bump(s, success: true, weight: 0.5) }
        case .thumbsDown: if let s = e.stance { bump(s, success: false, weight: 1) }
        case .edited:
            if let b = e.originalText, let a = e.finalText, b != a {
                recentEdits.append(EditPair(before: b, after: a))
                if recentEdits.count > 6 { recentEdits.removeFirst(recentEdits.count - 6) }
            }
        case .dismissed:
            for s in DraftStance.allCases { bump(s, success: false, weight: 0.15) }
        default: break
        }
    }

    /// Probabilidad estimada de que uses cada postura en este tema (mezcla global + tema).
    public func score(_ s: DraftStance, topic: String) -> Double {
        let g = global[s] ?? Beta()
        guard let t = byTopic[Self.topicKey(topic)]?[s], t.count > 0 else { return g.mean }
        let w = min(0.7, t.count / 10) // cuanto más datos del tema, más peso
        return g.mean * (1 - w) + t.mean * w
    }

    public func ranking(topic: String) -> [DraftStance] {
        DraftStance.allCases.sorted { score($0, topic: topic) > score($1, topic: topic) }
    }

    /// Predicción solo cuando hay datos suficientes.
    public func predictedFavorite(topic: String) -> DraftStance? {
        let used = (totals[.copied] ?? 0) + (totals[.composed] ?? 0)
        guard used >= 3 else { return nil }
        return ranking(topic: topic).first
    }

    /// Pistas para el prompt de redacción.
    public func promptHints(topic: String) -> String {
        var h: [String] = []
        if let l = preferredLength { h.append("Longitud que suele usar al final: ~\(Int(l)) caracteres.") }
        let used = (totals[.copied] ?? 0) + (totals[.composed] ?? 0)
        if used >= 3 {
            let r = ranking(topic: topic)
            h.append("En temas como este suele preferir el enfoque \"\(r[0].label)\"; dale el máximo cuidado.")
        }
        if !recentEdits.isEmpty {
            h.append("Ediciones recientes que hizo a borradores (aprende de ellas: qué quita, qué añade, cómo cambia el tono):")
            for e in recentEdits.suffix(3) { h.append("ANTES: \(e.before)\nDESPUÉS: \(e.after)") }
        }
        return h.joined(separator: "\n")
    }

    /// Métricas para el panel.
    public var conversionRate: Double {
        let shown = Double(totals[.shown] ?? 0)
        guard shown > 0 else { return 0 }
        return Double((totals[.copied] ?? 0) + (totals[.composed] ?? 0)) / shown
    }
}

/// Guarda eventos (JSONL) y el modelo de preferencias en disco.
public actor LearningStore {
    public static let shared = LearningStore()
    private var model: PreferenceModel
    private let modelURL: URL
    private let eventsURL: URL

    public init(directory: URL = AppStorage.directory()) {
        modelURL = directory.appendingPathComponent("preferences.json")
        eventsURL = directory.appendingPathComponent("interactions.jsonl")
        model = JSONFile.load(PreferenceModel.self, from: modelURL) ?? PreferenceModel()
    }

    public func record(_ e: InteractionEvent) {
        model.record(e)
        try? JSONFile.save(model, to: modelURL)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(e), let line = String(data: d, encoding: .utf8) {
            if let h = try? FileHandle(forWritingTo: eventsURL) {
                h.seekToEndOfFile(); h.write(Data((line + "\n").utf8)); try? h.close()
            } else {
                try? (line + "\n").write(to: eventsURL, atomically: true, encoding: .utf8)
            }
        }
    }

    public func current() -> PreferenceModel { model }
    public func reset() { model = PreferenceModel(); try? JSONFile.save(model, to: modelURL) }
}

/// Registro de lo que llevas gastado de tus créditos de la API, con límite opcional.
public actor SpendTracker {
    public static let shared = SpendTracker()
    public struct State: Codable, Sendable { public var totalUSD: Double = 0; public var analyses: Int = 0; public var limitUSD: Double = 100 }
    private var state: State
    private let url: URL

    public init(url: URL = AppStorage.file("spend.json")) {
        self.url = url
        state = JSONFile.load(State.self, from: url) ?? State()
    }

    public func add(_ usd: Double) { state.totalUSD += usd; state.analyses += 1; try? JSONFile.save(state, to: url) }
    public func setLimit(_ usd: Double) { state.limitUSD = usd; try? JSONFile.save(state, to: url) }
    public func snapshot() -> State { state }
    public func checkBudget() throws {
        if state.totalUSD >= state.limitUSD { throw XCError.budgetExceeded(spent: state.totalUSD, limit: state.limitUSD) }
    }
}
