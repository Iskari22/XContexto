import Foundation
import Testing
@testable import XCEngine
@testable import XCResearch
@testable import XCStyle
@testable import XCLearning

@Suite("Seguridad: la app nunca puede publicar")
struct SecurityTests {
    func req(_ url: String, _ method: String = "GET") -> URLRequest {
        var r = URLRequest(url: URL(string: url)!); r.httpMethod = method; return r
    }

    @Test func blocksPostingToX() {
        let p = NetworkPolicy()
        #expect(throws: XCError.self) { try p.check(req("https://api.x.com/2/tweets", "POST")) }
        #expect(throws: XCError.self) { try p.check(req("https://api.twitter.com/2/tweets", "POST")) }
        #expect(throws: XCError.self) { try p.check(req("https://x.com/i/api/graphql/CreateTweet", "POST")) }
        #expect(throws: XCError.self) { try p.check(req("https://x.com/home")) }
        #expect(throws: XCError.self) { try p.check(req("https://publish.twitter.com/oembed", "POST")) }
    }

    @Test func allowsOnlyExpectedTraffic() throws {
        let p = NetworkPolicy()
        try p.check(req("https://api.anthropic.com/v1/messages", "POST"))
        try p.check(req("https://publish.twitter.com/oembed?url=x"))
        try p.check(req("https://publish.x.com/oembed?url=x"))
        try p.check(req("https://es.wikipedia.org/w/rest.php/v1/search/page?q=a"))
        #expect(throws: XCError.self) { try p.check(req("https://evil.example.com/steal", "POST")) }
        #expect(throws: XCError.self) { try p.check(req("http://api.anthropic.com/v1/messages", "POST")) }
    }

    @Test func composeURLOnlyOpensEditor() {
        let u = PostingGuard.composeURL(reply: "Hola & adiós", inReplyTo: "123")
        #expect(u.host == "x.com" && u.path == "/intent/post")
        #expect(u.absoluteString.contains("in_reply_to=123"))
        #expect(PostingGuard.composeURL(reply: "x", inReplyTo: "1; DROP").absoluteString.contains("in_reply_to") == false)
    }

    @Test func redactsKeys() {
        #expect(!Redactor.redact("clave sk-ant-api03-ABCDEFGHIJKLMNOP fin").contains("ABCDEFGH"))
    }

    @Test func xLengthCountsURLsAs23() {
        #expect(PostingGuard.xLength("ver https://www.example.com/un/enlace/larguisimo/de/verdad") == 4 + 23)
    }
}

@Suite("Lectura de posts")
struct PostTests {
    @Test func parsesPostURLs() {
        #expect(PostURL(string: "https://x.com/elonmusk/status/1234567890?s=20")?.id == "1234567890")
        #expect(PostURL(string: "https://twitter.com/RTVE/status/42")?.handle == "RTVE")
        #expect(PostURL(string: "https://x.com/home") == nil)
        #expect(PostURL(string: "https://evil.com/a/status/1") == nil)
    }

    @Test func parsesOEmbedHTML() {
        let html = ##"<blockquote class="twitter-tweet"><p lang="es" dir="ltr">Hola &amp; adiós<br>línea 2 <a href="https://t.co/x">pic</a></p>&mdash; Autor (@a) <a href="#">1 ene</a></blockquote>"##
        #expect(OEmbedParser.tweetText(fromHTML: html) == "Hola & adiós\nlínea 2 pic")
    }

    @Test func keywordQueryPrefersEntities() {
        let q = KeywordExtractor.query(from: "La OTAN despliega tropas en Polonia tras la cumbre de #Vilna https://t.co/abc")
        #expect(q.contains("OTAN") && q.contains("Polonia") && q.contains("Vilna"))
    }

    @Test func stripsLeadingMentionsFromDrafts() {
        #expect(DraftWriter.stripLeadingMentions("@ana @luis Los datos dicen otra cosa") == "Los datos dicen otra cosa")
        #expect(DraftWriter.stripLeadingMentions("Según @INE_es el paro baja") == "Según @INE_es el paro baja")
    }

    @Test func normalizesURLsForVerification() {
        #expect(ResearchService.normalize("https://www.ElPais.com/a/b/?utm=1#x") == "elpais.com/a/b")
    }

    @Test func extractsJSONFromText() throws {
        let j = try JSONExtractor.extract("Aquí tienes:\n<json>{\"topic\": \"x\"}</json>")
        #expect(j["topic"]?.string == "x")
        #expect(throws: XCError.self) { try JSONExtractor.extract("sin json") }
    }
}

@Suite("Estilo")
struct StyleTests {
    @Test func importsArchive() throws {
        let js = #"""
        window.YTD.tweets.part0 = [
          {"tweet": {"full_text": "@fulano Totalmente de acuerdo, los datos del INE lo confirman", "favorite_count": "12", "retweet_count": "3", "in_reply_to_status_id_str": "99", "lang": "es"}},
          {"tweet": {"full_text": "RT @otro: algo", "favorite_count": "0", "retweet_count": "0", "lang": "es"}},
          {"tweet": {"full_text": "¿Alguien ha leído el informe del Banco de España? Muy interesante", "favorite_count": "40", "retweet_count": "10", "lang": "es"}}
        ]
        """#
        let samples = try ArchiveImporter.parseTweetsJS(Data(js.utf8))
        #expect(samples.count == 3)
        #expect(samples[0].text.hasPrefix("Totalmente"))
        let p = StyleProfile.build(from: samples)
        #expect(p.sampleCount == 2) // el RT se descarta
        #expect(p.questionRate == 0.5)
        #expect(!p.exemplars(for: "informe del Banco de España").isEmpty)
    }
}

@Suite("Aprendizaje")
struct LearningTests {
    @Test func learnsPreferredStance() {
        var m = PreferenceModel()
        for _ in 0..<5 {
            m.record(InteractionEvent(kind: .shown, postID: "1", topic: "guerra Ucrania"))
            m.record(InteractionEvent(kind: .copied, postID: "1", topic: "guerra Ucrania", stance: .critical, finalText: String(repeating: "a", count: 150)))
        }
        #expect(m.ranking(topic: "guerra Ucrania").first == .critical)
        #expect(m.predictedFavorite(topic: "guerra Ucrania") == .critical)
        #expect(abs((m.preferredLength ?? 0) - 150) < 1)
        #expect(m.conversionRate == 1)
    }

    @Test func topicSpecificPreferences() {
        var m = PreferenceModel()
        for _ in 0..<6 { m.record(InteractionEvent(kind: .copied, postID: "1", topic: "economía", stance: .neutral)) }
        for _ in 0..<6 { m.record(InteractionEvent(kind: .copied, postID: "2", topic: "geopolítica", stance: .critical)) }
        #expect(m.ranking(topic: "economía").first == .neutral)
        #expect(m.ranking(topic: "geopolítica").first == .critical)
    }

    @Test func remembersEdits() {
        var m = PreferenceModel()
        m.record(InteractionEvent(kind: .edited, postID: "1", topic: "t", stance: .neutral, originalText: "¡Gran punto! Los datos…", finalText: "Los datos…"))
        #expect(m.promptHints(topic: "t").contains("DESPUÉS: Los datos…"))
    }
}

@Suite("Recuperación de fallos")
struct DiagnosticsTests {
    @Test func remediesByError() {
        #expect(Remedy.forError(.rateLimited(retryAfter: 4), attempt: 1, fallbackModel: nil) == .retry(after: 4))
        #expect(Remedy.forError(.overloaded(status: 529), attempt: 2, fallbackModel: "claude-sonnet-5-5") == .switchModel(to: "claude-sonnet-5-5"))
        #expect(Remedy.forError(.unauthorized, attempt: 1, fallbackModel: nil) == .askUserForKey)
    }

    @Test func retriesThenSucceeds() async throws {
        let log = DiagLog(url: FileManager.default.temporaryDirectory.appendingPathComponent("diag-test-\(UUID()).jsonl"))
        actor Counter { var n = 0; func inc() -> Int { n += 1; return n } }
        let c = Counter()
        let v = try await withRecovery("test", log: log) { _ in
            if await c.inc() < 2 { throw XCError.rateLimited(retryAfter: 0.01) }
            return 7
        }
        #expect(v == 7)
        #expect(await log.errorCounts()["test"] == 1)
    }

    @Test func costEstimate() {
        let u = TokenUsage(model: "claude-opus-5-5", inputTokens: 1_000_000, outputTokens: 100_000, webSearches: 5)
        #expect(abs(u.estimatedCostUSD - (4 + 2 + 0.05)) < 0.0001)
    }
}

@Suite("Calibración")
struct CalibrationTests {
    @Test func picksRealReplies() throws {
        let js = #"""
        window.YTD.tweets.part0 = [
          {"tweet": {"full_text": "@ana Eso no es así: el PIB creció un 2,5% según el INE en 2024", "favorite_count": "5", "retweet_count": "1", "in_reply_to_status_id_str": "111", "in_reply_to_screen_name": "ana", "lang": "es"}},
          {"tweet": {"full_text": "@ana ok", "favorite_count": "0", "retweet_count": "0", "in_reply_to_status_id_str": "112", "in_reply_to_screen_name": "ana", "lang": "es"}},
          {"tweet": {"full_text": "Post propio sin respuesta a nadie, bastante largo para contar", "favorite_count": "9", "retweet_count": "0", "lang": "es"}}
        ]
        """#
        let c = Calibrator.candidates(from: try ArchiveImporter.parseTweetsJS(Data(js.utf8)), limit: 10)
        #expect(c.count == 1)
        #expect(c[0].replyToID == "111" && c[0].replyToHandle == "ana")
    }
}
