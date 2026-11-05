import Foundation

/// Un post de X tal como lo recibe la app (desde la extensión del navegador, Compartir en iOS o una URL).
public struct XPost: Codable, Sendable, Hashable {
    public var id: String
    public var url: URL?
    public var authorName: String
    public var handle: String
    public var text: String
    public var lang: String?

    public init(id: String, url: URL?, authorName: String, handle: String, text: String, lang: String? = nil) {
        self.id = id; self.url = url; self.authorName = authorName; self.handle = handle; self.text = text; self.lang = lang
    }
}

/// Entrada mínima: una URL de post, y opcionalmente el texto ya leído en la página.
public struct PostInput: Codable, Sendable, Hashable {
    public var url: URL?
    public var text: String?
    public var authorName: String?
    public var handle: String?

    public init(url: URL?, text: String? = nil, authorName: String? = nil, handle: String? = nil) {
        self.url = url; self.text = text; self.authorName = authorName; self.handle = handle
    }
}

public enum DraftStance: String, Codable, Sendable, CaseIterable, Hashable {
    case neutral, supportive, critical

    public var label: String {
        switch self {
        case .neutral: return "Neutro · amplía"
        case .supportive: return "A favor · refuerza"
        case .critical: return "Crítico · refuta"
        }
    }
}

public enum SourceKind: String, Codable, Sendable { case wikipedia, news, institution, factCheck, other }

public struct SourceRef: Codable, Sendable, Hashable, Identifiable {
    public var id: String { url }
    public var title: String
    public var url: String
    public var publisher: String
    public var kind: SourceKind
    /// `true` cuando la URL apareció en resultados reales de búsqueda/Wikipedia (no inventada por el modelo).
    public var verified: Bool

    public init(title: String, url: String, publisher: String, kind: SourceKind, verified: Bool) {
        self.title = title; self.url = url; self.publisher = publisher; self.kind = kind; self.verified = verified
    }
}

public struct Fact: Codable, Sendable, Hashable {
    public var text: String
    public var sources: [Int] // índices en ContextReport.sources
    public init(text: String, sources: [Int]) { self.text = text; self.sources = sources }
}

public enum ClaimVerdict: String, Codable, Sendable {
    case supported, disputed, `false`, unverifiable, opinion

    public var label: String {
        switch self {
        case .supported: return "Respaldado"
        case .disputed: return "Discutido"
        case .false: return "Erróneo"
        case .unverifiable: return "No verificable"
        case .opinion: return "Opinión"
        }
    }
}

public struct ClaimCheck: Codable, Sendable, Hashable {
    public var claim: String
    public var verdict: ClaimVerdict
    public var explanation: String
    public var sources: [Int]
    public init(claim: String, verdict: ClaimVerdict, explanation: String, sources: [Int]) {
        self.claim = claim; self.verdict = verdict; self.explanation = explanation; self.sources = sources
    }
}

public struct Perspective: Codable, Sendable, Hashable {
    public var label: String
    public var text: String
    public init(label: String, text: String) { self.label = label; self.text = text }
}

public struct ContextReport: Codable, Sendable, Hashable {
    public var topic: String
    public var summary: String
    public var background: String
    public var keyFacts: [Fact]
    public var claims: [ClaimCheck]
    public var perspectives: [Perspective]
    public var sources: [SourceRef]
    /// URLs que el modelo citó pero que no aparecieron en ninguna búsqueda real (se descartan).
    public var droppedUnverifiedSources: Int

    public init(topic: String, summary: String, background: String, keyFacts: [Fact], claims: [ClaimCheck],
                perspectives: [Perspective], sources: [SourceRef], droppedUnverifiedSources: Int) {
        self.topic = topic; self.summary = summary; self.background = background; self.keyFacts = keyFacts
        self.claims = claims; self.perspectives = perspectives; self.sources = sources
        self.droppedUnverifiedSources = droppedUnverifiedSources
    }
}

public struct ReplyDraft: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var stance: DraftStance
    public var text: String
    public var rationale: String
    public var sources: [Int]

    public init(id: UUID = UUID(), stance: DraftStance, text: String, rationale: String, sources: [Int]) {
        self.id = id; self.stance = stance; self.text = text; self.rationale = rationale; self.sources = sources
    }
}

public struct TokenUsage: Codable, Sendable, Hashable {
    public var model: String
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadTokens: Int
    public var cacheWriteTokens: Int
    public var webSearches: Int

    public init(model: String, inputTokens: Int = 0, outputTokens: Int = 0, cacheReadTokens: Int = 0,
                cacheWriteTokens: Int = 0, webSearches: Int = 0) {
        self.model = model; self.inputTokens = inputTokens; self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens; self.cacheWriteTokens = cacheWriteTokens; self.webSearches = webSearches
    }

    public var estimatedCostUSD: Double { Pricing.cost(of: self) }
}

public struct AnalysisResult: Codable, Sendable, Hashable {
    public var post: XPost
    public var report: ContextReport
    /// Ordenados por preferencia aprendida (el primero es el que la app predice que elegirás).
    public var drafts: [ReplyDraft]
    public var predictedFavorite: DraftStance?
    public var usage: [TokenUsage]
    public var generatedAt: Date
    public var durationSeconds: Double

    public init(post: XPost, report: ContextReport, drafts: [ReplyDraft], predictedFavorite: DraftStance?,
                usage: [TokenUsage], generatedAt: Date, durationSeconds: Double) {
        self.post = post; self.report = report; self.drafts = drafts; self.predictedFavorite = predictedFavorite
        self.usage = usage; self.generatedAt = generatedAt; self.durationSeconds = durationSeconds
    }

    public var totalCostUSD: Double { usage.reduce(0) { $0 + $1.estimatedCostUSD } }
}

public enum AnalysisStage: String, Sendable, Codable {
    case fetchingPost = "Leyendo el post"
    case researching = "Buscando contexto en fuentes reputadas"
    case drafting = "Escribiendo 3 borradores con tu estilo"
    case done = "Listo"
}
