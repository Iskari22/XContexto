import Foundation
import XCEngine

// CLI para probar el motor sin las apps:
//   xcx analyze <url-del-post> [--text "texto del post"]
//   xcx health
//   xcx set-key            (lee la clave de stdin y la guarda en el Llavero)
//   xcx import-archive <ruta/a/tweets.js> [--notes "tuteo, sin emojis"]
//   xcx metrics
//   xcx report             (exporta informe de diagnóstico)

let args = Array(CommandLine.arguments.dropFirst())
func arg(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}
func fail(_ msg: String) -> Never { FileHandle.standardError.write(Data((msg + "\n").utf8)); exit(1) }

let engine = XContextoEngine()

switch args.first {
case "analyze":
    guard args.count >= 2 else { fail("uso: xcx analyze <url> [--text \"...\"]") }
    let input = PostInput(url: URL(string: args[1]), text: arg("--text"))
    do {
        let r = try await engine.analyze(input) { stage in print("· \(stage.rawValue)…") }
        print("\n=== @\(r.post.handle): \(r.post.text)\n")
        print("TEMA: \(r.report.topic)\n\nRESUMEN: \(r.report.summary)\n\nANTECEDENTES: \(r.report.background)\n")
        print("HECHOS:"); r.report.keyFacts.forEach { print("  • \($0.text) \($0.sources.map { "[\($0 + 1)]" }.joined())") }
        print("\nAFIRMACIONES:"); r.report.claims.forEach { print("  • [\($0.verdict.label)] \($0.claim) — \($0.explanation)") }
        print("\nFUENTES:"); r.report.sources.enumerated().forEach { print("  [\($0 + 1)] \($1.publisher): \($1.title) — \($1.url)") }
        if r.report.droppedUnverifiedSources > 0 { print("  (descartadas \(r.report.droppedUnverifiedSources) URLs no verificadas)") }
        print("\nBORRADORES\(r.predictedFavorite.map { " (predicción: \($0.label))" } ?? ""):")
        for d in r.drafts {
            print("\n— \(d.stance.label) [\(PostingGuard.xLength(d.text)) car.]\n\(d.text)\n  ↳ \(d.rationale)")
        }
        print(String(format: "\nCoste estimado: $%.4f · %.1f s", r.totalCostUSD, r.durationSeconds))
    } catch { fail("Error: \(error.localizedDescription)") }

case "fetch":
    // Lee un post sin llamar a la API de Claude (gratis).
    guard args.count >= 2 else { fail("uso: xcx fetch <url>") }
    do {
        let p = try await PostFetcher().resolve(PostInput(url: URL(string: args[1])))
        print("@\(p.handle) (\(p.authorName)) [\(p.lang ?? "?")]: \(p.text)")
        let wiki = await WikipediaClient().articles(for: p.text, lang: p.lang ?? "es")
        print("Wikipedia (\(KeywordExtractor.query(from: p.text))):"); wiki.forEach { print("  • \($0.title) — \($0.url)") }
    } catch { fail(error.localizedDescription) }

case "calibrate":
    // Calibra la app con tus respuestas reales del archivo de X.
    guard args.count >= 2 else { fail("uso: xcx calibrate <tweets.js> [--n 60] [--budget 40] [--parallel 4]") }
    do {
        let samples = try ArchiveImporter.importFile(at: URL(fileURLWithPath: args[1]))
        if StyleStore.load().sampleCount == 0 {
            try StyleStore.save(StyleProfile.build(from: samples))
            print("Perfil de estilo creado con \(samples.count) posts.")
        }
        let n = Int(arg("--n") ?? "") ?? 60
        let budget = Double(arg("--budget") ?? "") ?? 40
        let par = Int(arg("--parallel") ?? "") ?? 4
        print(String(format: "Calibrando hasta %d respuestas, %d en paralelo, tope %.0f USD…", n, par, budget))
        let r = try await Calibrator(engine: engine).run(samples: samples, limit: n, budgetUSD: budget, concurrency: par) { print($0) }
        print(String(format: "\nCasos: %d (fallidos %d) · parecido de estilo medio: %.1f/10 · coste: %.2f USD",
                     r.cases.count, r.failures, r.averageStyleScore, r.totalCostUSD))
        print("Posturas en tus respuestas reales: " + r.stanceShare.map { String(format: "%@ %.0f%%", $0.key, $0.value * 100) }.joined(separator: ", "))
        if !r.styleGuide.isEmpty { print("\nGUÍA DE ESTILO APRENDIDA (ya guardada en tu perfil):\n\(r.styleGuide)") }
    } catch { fail(error.localizedDescription) }

case "health":
    for h in await engine.healthCheck() {
        print("\(h.ok ? "✅" : "❌") \(h.name): \(h.detail)\(h.fix.map { " → \($0)" } ?? "")")
    }

case "set-key":
    print("Pega tu clave de la API y pulsa Enter:", terminator: " ")
    guard let line = readLine(strippingNewline: true) else { fail("sin entrada") }
    do { try KeychainStore.save(line); print("Guardada en el Llavero.") } catch { fail(error.localizedDescription) }

case "import-archive":
    guard args.count >= 2 else { fail("uso: xcx import-archive <tweets.js>") }
    do {
        let samples = try ArchiveImporter.importFile(at: URL(fileURLWithPath: args[1]))
        let p = StyleProfile.build(from: samples, manualNotes: arg("--notes") ?? StyleStore.load().manualNotes)
        try StyleStore.save(p)
        print("Importados \(samples.count) posts. Perfil:\n\(p.promptDescription())")
    } catch { fail(error.localizedDescription) }

case "metrics":
    let m = await LearningStore.shared.current()
    let s = await SpendTracker.shared.snapshot()
    print(String(format: "Gasto: %.2f / %.2f USD en %d análisis", s.totalUSD, s.limitUSD, s.analyses))
    print(String(format: "Uso de borradores: %.0f%%", m.conversionRate * 100))
    for st in DraftStance.allCases { print(String(format: "  %@: %.0f%%", st.label, m.score(st, topic: "") * 100)) }

case "report":
    let r = await DiagnosticReport.build(health: await engine.healthCheck())
    do { print("Informe: \(try r.writeToDisk().path)") } catch { fail(error.localizedDescription) }

default:
    print("Comandos: analyze, health, set-key, import-archive, metrics, report")
}
