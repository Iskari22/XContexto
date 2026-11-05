import Foundation

/// Calibración con tu historial: para cada post al que respondiste de verdad, la app genera sus 3 borradores
/// y Claude los compara con tu respuesta real. Resultado:
/// 1. Preferencias precargadas (qué postura usas según el tema).
/// 2. Una guía de estilo escrita a partir de las diferencias, que se guarda en tu perfil.
/// 3. Una puntuación de parecido a tu voz, para medir mejoras.
public struct CalibrationCase: Codable, Sendable {
    public var postURL: String
    public var postText: String
    public var topic: String
    public var realReply: String
    public var drafts: [ReplyDraft]
    public var matchedStance: DraftStance?
    public var styleScores: [String: Int] // postura → 1-10
    public var differences: String
    public var costUSD: Double
}

public struct CalibrationReport: Codable, Sendable {
    public var date: Date
    public var cases: [CalibrationCase]
    public var failures: Int
    public var averageStyleScore: Double
    public var stanceShare: [String: Double]
    public var styleGuide: String
    public var totalCostUSD: Double
}

public actor Calibrator {
    let engine: XContextoEngine
    let claude: ClaudeClient

    public init(engine: XContextoEngine) {
        self.engine = engine
        self.claude = engine.claude
    }

    /// Tus respuestas del archivo que se pueden usar (respuesta con texto suficiente y post original identificable).
    public static func candidates(from samples: [StyleSample], limit: Int) -> [StyleSample] {
        var seen = Set<String>()
        return samples.filter { s in
            guard let id = s.replyToID, let h = s.replyToHandle, !h.isEmpty, s.text.count >= 40,
                  !s.text.hasPrefix("RT @"), seen.insert(id).inserted else { return false }
            return true
        }
        .sorted { ($0.likes + $0.retweets) > ($1.likes + $1.retweets) }
        .prefix(limit).map { $0 }
    }

    static let judgeSchema: JSONValue = [
        "type": "object", "additionalProperties": false,
        "required": ["closest_stance", "scores", "differences"],
        "properties": [
            "closest_stance": ["type": "string", "enum": ["neutral", "supportive", "critical"]],
            "scores": [
                "type": "object", "additionalProperties": false,
                "required": ["neutral", "supportive", "critical"],
                "properties": ["neutral": ["type": "integer"], "supportive": ["type": "integer"], "critical": ["type": "integer"]],
            ],
            "differences": ["type": "string"],
        ],
    ]

    func judge(post: String, real: String, drafts: [ReplyDraft]) async throws -> (DraftStance, [String: Int], String, TokenUsage) {
        let list = drafts.map { "[\($0.stance.rawValue)] \($0.text)" }.joined(separator: "\n\n")
        let body: [String: JSONValue] = [
            "max_tokens": 4000,
            "system": "Comparas borradores generados por una IA con la respuesta real que escribió una persona en X. Sé concreto y honesto.",
            "messages": [["role": "user", "content": .string("""
            <post_original>\(post)</post_original>
            <respuesta_real_del_usuario>\(real)</respuesta_real_del_usuario>
            <borradores>\(list)</borradores>

            1. closest_stance: ¿a qué postura (neutral/supportive/critical) se parece más la intención de la respuesta real?
            2. scores: de 1 a 10, cuánto se parece cada borrador al ESTILO de la persona (vocabulario, longitud, tono, puntuación, emojis), no a su contenido.
            3. differences: en 2-4 frases, qué hace la persona que los borradores no hacen, y viceversa (concreto: palabras, estructura, tono).
            """)]],
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": Self.judgeSchema]],
        ]
        let msg = try await claude.send(body)
        let j = try JSONExtractor.extract(msg.text)
        let stance = DraftStance(rawValue: j["closest_stance"]?.string ?? "") ?? .neutral
        var scores: [String: Int] = [:]
        for s in DraftStance.allCases { scores[s.rawValue] = j["scores"]?[s.rawValue]?.int ?? 0 }
        return (stance, scores, j["differences"]?.string ?? "", msg.usage)
    }

    func writeGuide(_ cases: [CalibrationCase], current: StyleProfile) async throws -> (String, TokenUsage) {
        let notes = cases.prefix(80).map { "- Post: \($0.postText.prefix(160))\n  Real: \($0.realReply)\n  Diferencias: \($0.differences)" }
            .joined(separator: "\n")
        let body: [String: JSONValue] = [
            "max_tokens": 6000,
            "system": "Eres un editor que escribe guías de estilo precisas para imitar la voz de una persona en X.",
            "messages": [["role": "user", "content": .string("""
            Perfil actual:
            \(current.promptDescription())

            Comparaciones entre borradores de IA y sus respuestas reales:
            \(notes)

            Escribe una guía de estilo de 8-15 viñetas, en español, con instrucciones concretas y accionables para que una IA
            escriba sus respuestas como él: longitud, apertura, vocabulario y expresiones, uso de datos y fuentes, ironía,
            puntuación, emojis, cómo discrepa, qué evitar. Incluye 2-3 ejemplos de frases típicas suyas tomadas de las respuestas reales.
            Solo la guía, sin introducción.
            """)]],
            "output_config": ["effort": "high"],
        ]
        let msg = try await claude.send(body)
        return (msg.text.trimmingCharacters(in: .whitespacesAndNewlines), msg.usage)
    }

    /// Ejecuta la calibración con hasta `concurrency` posts a la vez y se para al llegar a `budgetUSD`.
    public func run(samples: [StyleSample], limit: Int, budgetUSD: Double, concurrency: Int = 4,
                    log: @escaping @Sendable (String) -> Void) async throws -> CalibrationReport {
        let base = StyleStore.load()
        let cands = Self.candidates(from: samples, limit: limit)
        log("Respuestas utilizables: \(cands.count)")
        var cases: [CalibrationCase] = []
        var failures = 0
        var spent = 0.0
        var next = 0

        await withTaskGroup(of: Result<CalibrationCase, Error>.self) { group in
            func launch(_ s: StyleSample) {
                // Sin fuga: quitamos la respuesta real de los ejemplos de estilo que verá el redactor.
                var style = base
                style.samples.removeAll { $0.text == s.text }
                let engine = self.engine
                group.addTask {
                    do {
                        let url = URL(string: "https://x.com/\(s.replyToHandle!)/status/\(s.replyToID!)")!
                        let r = try await engine.analyze(PostInput(url: url), force: true, styleOverride: style, recordLearning: false)
                        let (stance, scores, diff, u) = try await self.judge(post: r.post.text, real: s.text, drafts: r.drafts)
                        await SpendTracker.shared.add(u.estimatedCostUSD)
                        return .success(CalibrationCase(postURL: url.absoluteString, postText: r.post.text, topic: r.report.topic,
                                                        realReply: s.text, drafts: r.drafts, matchedStance: stance, styleScores: scores,
                                                        differences: diff, costUSD: r.totalCostUSD + u.estimatedCostUSD))
                    } catch { return .failure(error) }
                }
            }
            while next < min(concurrency, cands.count) { launch(cands[next]); next += 1 }
            for await res in group {
                switch res {
                case .success(let c):
                    cases.append(c); spent += c.costUSD
                    let best = c.styleScores.values.max() ?? 0
                    log(String(format: "✓ %d/%d · %@ · estilo %d/10 · %.3f USD (total %.2f)", cases.count + failures, cands.count,
                               c.matchedStance?.rawValue ?? "?", best, c.costUSD, spent))
                case .failure(let e):
                    failures += 1
                    log("✗ \(cases.count + failures)/\(cands.count) · \(e.localizedDescription)")
                }
                if next < cands.count, spent < budgetUSD { launch(cands[next]); next += 1 }
            }
        }

        // Aprendizaje: cada respuesta real cuenta como si hubieras elegido esa postura con ese texto.
        for c in cases {
            await LearningStore.shared.record(InteractionEvent(kind: .composed, postID: c.postURL, topic: c.topic,
                                                               stance: c.matchedStance, finalText: c.realReply))
        }

        var guide = ""
        if cases.count >= 3 {
            log("Escribiendo tu guía de estilo con \(cases.count) comparaciones…")
            let (g, u) = try await writeGuide(cases, current: base)
            await SpendTracker.shared.add(u.estimatedCostUSD)
            spent += u.estimatedCostUSD
            guide = g
            var updated = StyleStore.load()
            updated.learnedGuide = g
            try StyleStore.save(updated)
        }

        let scores = cases.compactMap { $0.styleScores.values.max() }
        let share = Dictionary(grouping: cases.compactMap(\.matchedStance), by: \.rawValue).mapValues { Double($0.count) / Double(max(cases.count, 1)) }
        let report = CalibrationReport(date: Date(), cases: cases, failures: failures,
                                       averageStyleScore: scores.isEmpty ? 0 : Double(scores.reduce(0, +)) / Double(scores.count),
                                       stanceShare: share, styleGuide: guide, totalCostUSD: spent)
        try? JSONFile.save(report, to: AppStorage.file("calibracion-\(Int(Date().timeIntervalSince1970)).json"))
        return report
    }
}
