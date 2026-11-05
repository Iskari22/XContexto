import Foundation
@_exported import XCCore
@_exported import XCSecurity
@_exported import XCDiagnostics
@_exported import XCClaude
@_exported import XCResearch
@_exported import XCStyle
@_exported import XCLearning

/// Une todos los paquetes: post → contexto → borradores → orden por preferencias.
public actor XContextoEngine {
    public let claude: ClaudeClient
    let fetcher: PostFetcher
    let research: ResearchService
    let writer: DraftWriter
    let learning: LearningStore
    let spend: SpendTracker
    private var cache: [String: AnalysisResult] = [:]

    public init(config: ClaudeConfig = ClaudeConfig(), learning: LearningStore = .shared, spend: SpendTracker = .shared,
                apiKey: (@Sendable () throws -> String)? = nil) {
        let http = GuardedHTTPClient()
        let c = apiKey.map { ClaudeClient(config: config, http: http, apiKey: $0) } ?? ClaudeClient(config: config, http: http)
        claude = c
        fetcher = PostFetcher(http: http)
        research = ResearchService(claude: c, wiki: WikipediaClient(http: http))
        writer = DraftWriter(claude: c)
        self.learning = learning
        self.spend = spend
    }

    public func analyze(_ input: PostInput, force: Bool = false,
                        progress: (@Sendable (AnalysisStage) -> Void)? = nil) async throws -> AnalysisResult {
        let start = Date()
        try await spend.checkBudget()
        let fallback = claude.config.fallbackModel

        progress?(.fetchingPost)
        let fetcher = self.fetcher
        let post = try await withRecovery("post", maxAttempts: 2) { _ in try await fetcher.resolve(input) }
        if !force, let hit = cache[post.id] { return hit }

        // Estilo y preferencias se cargan en paralelo con la investigación.
        async let styleTask = Task.detached { StyleStore.load() }.value
        async let prefsTask = learning.current()

        progress?(.researching)
        let research = self.research
        let (report, u1): (ContextReport, TokenUsage)
        do {
            (report, u1) = try await withRecovery("research", fallbackModel: fallback) { m in
                try await research.research(post, model: m)
            }
        } catch let e as XCError where !(e == .unauthorized || e == .missingAPIKey) {
            // Arreglo automático: si la búsqueda web falla, seguimos solo con Wikipedia.
            await DiagLog.shared.log(.warning, "research", "Sin búsqueda web: \(e.localizedDescription)", remedy: Remedy.continueWithoutWebSearch.description)
            (report, u1) = try await withRecovery("research-wiki", fallbackModel: fallback) { m in
                try await research.research(post, model: m, useWebSearch: false)
            }
        }

        progress?(.drafting)
        let style = await styleTask
        let prefs = await prefsTask
        let writer = self.writer
        let (drafts, u2) = try await withRecovery("drafts", fallbackModel: fallback) { m in
            try await writer.write(post: post, report: report, style: style, prefs: prefs, model: m)
        }

        let order = prefs.ranking(topic: report.topic)
        let sorted = drafts.sorted { (order.firstIndex(of: $0.stance) ?? 0) < (order.firstIndex(of: $1.stance) ?? 0) }
        let result = AnalysisResult(post: post, report: report, drafts: sorted, predictedFavorite: prefs.predictedFavorite(topic: report.topic),
                                    usage: [u1, u2], generatedAt: Date(), durationSeconds: Date().timeIntervalSince(start))
        cache[post.id] = result
        await spend.add(result.totalCostUSD)
        await learning.record(InteractionEvent(kind: .shown, postID: post.id, topic: report.topic))
        await DiagLog.shared.log(.info, "engine", String(format: "Análisis %@ en %.1fs, $%.4f", post.id, result.durationSeconds, result.totalCostUSD))
        progress?(.done)
        return result
    }

    /// Rehace solo los borradores (sin repetir la investigación): más barato.
    public func regenerateDrafts(for result: AnalysisResult) async throws -> AnalysisResult {
        try await spend.checkBudget()
        let style = StyleStore.load()
        let prefs = await learning.current()
        let writer = self.writer
        let (drafts, u) = try await withRecovery("drafts", fallbackModel: claude.config.fallbackModel) { m in
            try await writer.write(post: result.post, report: result.report, style: style, prefs: prefs, model: m)
        }
        var r = result
        let order = prefs.ranking(topic: r.report.topic)
        r.drafts = drafts.sorted { (order.firstIndex(of: $0.stance) ?? 0) < (order.firstIndex(of: $1.stance) ?? 0) }
        r.usage.append(u)
        cache[r.post.id] = r
        await spend.add(u.estimatedCostUSD)
        await learning.record(InteractionEvent(kind: .regenerated, postID: r.post.id, topic: r.report.topic))
        return r
    }

    public func record(_ kind: InteractionKind, result: AnalysisResult, draft: ReplyDraft? = nil, finalText: String? = nil) async {
        await learning.record(InteractionEvent(kind: kind, postID: result.post.id, topic: result.report.topic, stance: draft?.stance,
                                               originalText: draft?.text, finalText: finalText ?? draft?.text))
    }

    /// Chequeo de salud: qué funciona, qué no, y cómo arreglarlo.
    public func healthCheck() async -> [HealthItem] {
        var items: [HealthItem] = []
        let hasKey = (try? KeychainStore.resolveAPIKey()) != nil
        items.append(HealthItem(name: "Clave de la API", ok: hasKey, detail: hasKey ? "Guardada" : "No configurada",
                                fix: hasKey ? nil : "Añádela en Ajustes (console.anthropic.com → API Keys)"))
        if hasKey {
            do { try await claude.ping(); items.append(HealthItem(name: "API de Anthropic", ok: true, detail: "Conectada", fix: nil)) } catch {
                items.append(HealthItem(name: "API de Anthropic", ok: false, detail: error.localizedDescription,
                                        fix: (error as? XCError) == .unauthorized ? "Genera una clave nueva en la Consola" : "Revisa tu conexión"))
            }
        }
        let wiki = await WikipediaClient().articles(for: "Unión Europea", lang: "es", limit: 1)
        items.append(HealthItem(name: "Wikipedia", ok: !wiki.isEmpty, detail: wiki.isEmpty ? "Sin respuesta" : "Accesible",
                                fix: wiki.isEmpty ? "Revisa tu conexión" : nil))
        let blocked = (try? NetworkPolicy().check({ var r = URLRequest(url: URL(string: "https://api.x.com/2/tweets")!); r.httpMethod = "POST"; return r }())) == nil
        items.append(HealthItem(name: "Bloqueo de publicación", ok: blocked, detail: blocked ? "Activo: la app no puede publicar en X" : "¡INACTIVO!",
                                fix: blocked ? nil : "Reinstala la app"))
        let s = await spend.snapshot()
        items.append(HealthItem(name: "Gasto", ok: s.totalUSD < s.limitUSD,
                                detail: String(format: "%.2f de %.2f USD (%d análisis)", s.totalUSD, s.limitUSD, s.analyses),
                                fix: s.totalUSD < s.limitUSD ? nil : "Sube el límite en Ajustes"))
        let errs = await DiagLog.shared.errorCounts()
        let total = errs.values.reduce(0, +)
        items.append(HealthItem(name: "Errores (24 h)", ok: total < 10, detail: total == 0 ? "Ninguno" : errs.map { "\($0.key): \($0.value)" }.joined(separator: ", "),
                                fix: total < 10 ? nil : "Exporta el diagnóstico y pásaselo a Claude Code"))
        return items
    }
}
