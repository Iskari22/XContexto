import Foundation
import XCCore
import XCSecurity
import XCDiagnostics

public struct ClaudeConfig: Sendable {
    /// Modelo principal. Opus 5.5 da la mejor calidad en investigación y redacción.
    public var model: String = "claude-opus-5-5"
    /// Modelo de respaldo solo si la API está saturada tras varios reintentos.
    public var fallbackModel: String = "claude-sonnet-5-5"
    public var researchEffort: String = "medium"
    public var draftingEffort: String = "medium"
    public var timeout: TimeInterval = 180
    public init() {}
}

/// Respuesta de la Messages API reducida a lo que usa la app.
public struct ClaudeMessage: Sendable {
    public var id: String
    public var model: String
    public var stopReason: String?
    public var content: [JSONValue]
    public var usage: TokenUsage

    public var text: String {
        content.filter { $0["type"]?.string == "text" }.compactMap { $0["text"]?.string }.joined()
    }

    /// Resultados reales de la búsqueda web: la única fuente de URLs "verificadas".
    public var webSearchResults: [(url: String, title: String)] {
        content.filter { $0["type"]?.string == "web_search_tool_result" }
            .compactMap { $0["content"]?.array } // si hay error, `content` es un objeto y se ignora
            .flatMap { $0 }
            .compactMap { r in
                guard r["type"]?.string == "web_search_result", let u = r["url"]?.string else { return nil }
                return (u, r["title"]?.string ?? u)
            }
    }

    /// URLs citadas por el modelo dentro del texto (citas de la búsqueda web).
    public var citedURLs: [String] {
        content.compactMap { $0["citations"]?.array }.flatMap { $0 }.compactMap { $0["url"]?.string }
    }
}

public actor ClaudeClient {
    public static let apiVersion = "2026-10-21"
    public nonisolated let config: ClaudeConfig
    private let http: GuardedHTTPClient
    private let apiKey: @Sendable () throws -> String
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    public init(config: ClaudeConfig = ClaudeConfig(), http: GuardedHTTPClient = GuardedHTTPClient(),
                apiKey: @escaping @Sendable () throws -> String = { try KeychainStore.resolveAPIKey() }) {
        self.config = config; self.http = http; self.apiKey = apiKey
    }

    /// Envía una petición a /v1/messages. `body` no lleva `model`: se añade aquí.
    public func send(_ body: [String: JSONValue], model: String? = nil) async throws -> ClaudeMessage {
        var full = body
        let usedModel = model ?? config.model
        full["model"] = .string(usedModel)
        // Si el filtro de seguridad declina, la API reintenta sola con el modelo de respaldo recomendado.
        full["fallbacks"] = "default"

        var req = URLRequest(url: endpoint, timeoutInterval: config.timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(try apiKey(), forHTTPHeaderField: "x-api-key")
        req.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        req.httpBody = try JSONValue.object(full).encoded()

        let (data, resp) = try await http.data(for: req)
        let json = (try? JSONValue.decode(data)) ?? .null

        switch resp.statusCode {
        case 200: break
        case 401, 403: throw XCError.unauthorized
        case 429:
            let after = (resp.value(forHTTPHeaderField: "retry-after")).flatMap(Double.init)
            throw XCError.rateLimited(retryAfter: after)
        case 500, 502, 503, 504, 529: throw XCError.overloaded(status: resp.statusCode)
        default:
            let msg = json["error"]?["message"]?.string ?? String(data: data.prefix(300), encoding: .utf8) ?? ""
            if msg.lowercased().contains("credit balance") { throw XCError.noCredits }
            throw XCError.api(status: resp.statusCode, message: msg)
        }

        let stop = json["stop_reason"]?.string
        if stop == "refusal" { throw XCError.refusal(category: json["stop_details"]?["category"]?.string) }
        if stop == "max_tokens" { throw XCError.truncated }

        let u = json["usage"]
        let usage = TokenUsage(
            model: json["model"]?.string ?? usedModel,
            inputTokens: u?["input_tokens"]?.int ?? 0,
            outputTokens: u?["output_tokens"]?.int ?? 0,
            cacheReadTokens: u?["cache_read_input_tokens"]?.int ?? 0,
            cacheWriteTokens: u?["cache_creation_input_tokens"]?.int ?? 0,
            webSearches: u?["server_tool_use"]?["web_search_requests"]?.int ?? 0
        )
        await DiagLog.shared.log(.info, "claude",
            "OK \(usage.model) in=\(usage.inputTokens) out=\(usage.outputTokens) web=\(usage.webSearches) $\(String(format: "%.4f", usage.estimatedCostUSD))")
        return ClaudeMessage(id: json["id"]?.string ?? "", model: usage.model, stopReason: stop,
                             content: json["content"]?.array ?? [], usage: usage)
    }

    /// Comprobación de salud barata: lista de modelos (GET, sin coste).
    public func ping() async throws {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=1")!, timeoutInterval: 15)
        req.setValue(try apiKey(), forHTTPHeaderField: "x-api-key")
        req.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        let (_, resp) = try await http.data(for: req)
        if resp.statusCode == 401 || resp.statusCode == 403 { throw XCError.unauthorized }
        guard resp.statusCode == 200 else { throw XCError.api(status: resp.statusCode, message: "ping") }
    }
}

/// Extrae el primer objeto JSON de un texto (dentro de <json>…</json>, ```json … ``` o suelto).
public enum JSONExtractor {
    public static func extract(_ text: String) throws -> JSONValue {
        var candidate = text
        if let r1 = text.range(of: "<json>"), let r2 = text.range(of: "</json>", range: r1.upperBound..<text.endIndex) {
            candidate = String(text[r1.upperBound..<r2.lowerBound])
        } else if let r1 = text.range(of: "```json"), let r2 = text.range(of: "```", range: r1.upperBound..<text.endIndex) {
            candidate = String(text[r1.upperBound..<r2.lowerBound])
        } else if let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}") {
            candidate = String(text[a...b])
        }
        do { return try JSONValue.decode(Data(candidate.utf8)) } catch {
            throw XCError.decoding("no encontré JSON válido en la respuesta")
        }
    }
}
