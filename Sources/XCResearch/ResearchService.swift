import Foundation
import XCCore
import XCClaude
import XCDiagnostics

/// Amplía el contexto de un post: Wikipedia y búsqueda web en fuentes reputadas, y verificación de afirmaciones.
public struct ResearchService: Sendable {
    let claude: ClaudeClient
    let wiki: WikipediaClient

    public init(claude: ClaudeClient, wiki: WikipediaClient = WikipediaClient()) {
        self.claude = claude; self.wiki = wiki
    }

    static let system = """
    Eres un analista de documentación riguroso. Te paso un post de X y extractos de Wikipedia.
    Tu trabajo: ampliar el contexto del post con información verificable de fuentes reputadas, y comprobar sus afirmaciones.

    Reglas:
    - Usa la búsqueda web para encontrar información reciente y fiable. Prioriza agencias, prensa de referencia, instituciones y verificadores.
    - Separa hechos de opiniones. No tomes partido: describe las posturas relevantes con sus mejores argumentos.
    - Cada hecho y cada veredicto debe llevar las URLs concretas de donde sale. No cites URLs que no hayas visto en los resultados.
    - Si algo no se puede verificar, dilo (verdict "unverifiable"). Si es un juicio de valor, usa "opinion".
    - Escribe en el idioma del post.

    Responde SOLO con un objeto JSON dentro de <json></json> con esta forma:
    {"topic": "tema en 3-6 palabras",
     "summary": "qué está pasando, 2-3 frases",
     "background": "antecedentes necesarios para entenderlo, 3-5 frases",
     "key_facts": [{"text": "dato concreto con cifras/fechas", "source_urls": ["https://..."]}],
     "claims": [{"claim": "afirmación del post", "verdict": "supported|disputed|false|unverifiable|opinion",
                 "explanation": "por qué, con datos", "source_urls": ["https://..."]}],
     "perspectives": [{"label": "postura", "text": "su argumento principal"}]}
    """

    public func research(_ post: XPost, model: String? = nil, useWebSearch: Bool = true) async throws -> (ContextReport, TokenUsage) {
        let lang = post.lang ?? "es"
        // Wikipedia arranca en paralelo y no bloquea si falla.
        async let wikiTask = wiki.articles(for: post.text, lang: lang)
        let articles = await wikiTask

        var wikiBlock = ""
        for a in articles { wikiBlock += "\n### \(a.title) (\(a.url))\n\(a.extract.prefix(1200))\n" }

        let user = """
        <post autor="\(post.authorName) (@\(post.handle))" url="\(post.url?.absoluteString ?? "")">
        \(post.text)
        </post>

        <wikipedia>\(wikiBlock.isEmpty ? "(sin resultados)" : wikiBlock)</wikipedia>
        """

        var body: [String: JSONValue] = [
            "max_tokens": 16000,
            "system": [["type": "text", "text": .string(Self.system), "cache_control": ["type": "ephemeral"]]],
            "messages": [["role": "user", "content": .string(user)]],
            "output_config": ["effort": .string(claude.config.researchEffort)],
        ]
        if useWebSearch {
            body["tools"] = [[
                "type": "web_search_20260209", "name": "web_search", "max_uses": 5,
                "allowed_domains": .array(TrustedSources.deduplicated.map { .string($0) }),
            ]]
        }

        let msg = try await claude.send(body, model: model)
        let json = try JSONExtractor.extract(msg.text)

        // Solo se aceptan URLs que aparecieron de verdad en búsqueda o Wikipedia.
        var verified: [String: String] = [:]
        for r in msg.webSearchResults { verified[normalize(r.url)] = r.title }
        for a in articles { verified[normalize(a.url)] = a.title }
        for u in msg.citedURLs where verified[normalize(u)] == nil { verified[normalize(u)] = TrustedSources.publisher(for: u) }

        var sources: [SourceRef] = []
        var index: [String: Int] = [:]
        var dropped = 0
        func refs(_ v: JSONValue?) -> [Int] {
            (v?.array ?? []).compactMap { $0.string }.compactMap { raw in
                let key = normalize(raw)
                guard let title = verified[key] else { dropped += 1; return nil }
                if let i = index[key] { return i }
                sources.append(SourceRef(title: title, url: raw, publisher: TrustedSources.publisher(for: raw),
                                         kind: TrustedSources.kind(for: raw), verified: true))
                index[key] = sources.count - 1
                return sources.count - 1
            }
        }

        let facts = (json["key_facts"]?.array ?? []).compactMap { f -> Fact? in
            guard let t = f["text"]?.string else { return nil }
            return Fact(text: t, sources: refs(f["source_urls"]))
        }
        let claims = (json["claims"]?.array ?? []).compactMap { c -> ClaimCheck? in
            guard let t = c["claim"]?.string else { return nil }
            return ClaimCheck(claim: t, verdict: ClaimVerdict(rawValue: c["verdict"]?.string ?? "") ?? .unverifiable,
                              explanation: c["explanation"]?.string ?? "", sources: refs(c["source_urls"]))
        }
        let perspectives = (json["perspectives"]?.array ?? []).compactMap { p -> Perspective? in
            guard let l = p["label"]?.string, let t = p["text"]?.string else { return nil }
            return Perspective(label: l, text: t)
        }
        // Añade las páginas de Wikipedia consultadas aunque no se citaran.
        for a in articles where index[normalize(a.url)] == nil {
            sources.append(SourceRef(title: a.title, url: a.url, publisher: TrustedSources.publisher(for: a.url), kind: .wikipedia, verified: true))
            index[normalize(a.url)] = sources.count - 1
        }
        if dropped > 0 { await DiagLog.shared.log(.warning, "research", "Descartadas \(dropped) URLs no verificadas") }

        let report = ContextReport(topic: json["topic"]?.string ?? "", summary: json["summary"]?.string ?? "",
                                   background: json["background"]?.string ?? "", keyFacts: facts, claims: claims,
                                   perspectives: perspectives, sources: sources, droppedUnverifiedSources: dropped)
        return (report, msg.usage)
    }

    func normalize(_ url: String) -> String {
        var s = url.lowercased()
        for p in ["https://", "http://", "www."] where s.hasPrefix(p) { s.removeFirst(p.count) }
        if let q = s.firstIndex(where: { $0 == "?" || $0 == "#" }) { s = String(s[..<q]) }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
